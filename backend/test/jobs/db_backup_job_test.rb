require "test_helper"
require "tmpdir"

class DbBackupJobTest < ActiveSupport::TestCase
  Status = Data.define(:successful, :exitstatus) do
    def success? = successful
  end

  def setup
    @backup_directory = Dir.mktmpdir("db-backup-job-test")
    ENV["BACKUP_ACCESS_KEY_ID"] = "test_access_key"
    ENV["BACKUP_SECRET_ACCESS_KEY"] = "test_secret_key"
    ENV["BACKUP_LOCAL_DIR"] = @backup_directory
    ENV["DEPLOY_USER"] = "deploy"
    ENV["BACKUP_ENDPOINT"] = "https://s3.example.com"
    ENV["BACKUP_BUCKET"] = "test-bucket"
  end

  def teardown
    FileUtils.remove_entry(@backup_directory)
    %w[
      BACKUP_ACCESS_KEY_ID
      BACKUP_SECRET_ACCESS_KEY
      BACKUP_LOCAL_DIR
      DEPLOY_USER
      BACKUP_ENDPOINT
      BACKUP_BUCKET
    ].each { |key| ENV.delete(key) }
  end

  def test_perform_uploads_verifies_and_prunes_backups
    outdated = "#{db_name}_#{61.days.ago.to_i}.sql"
    recent = "#{db_name}_#{1.day.ago.to_i}.sql"
    job, commands = build_job do |_, command|
      if command.first == "/usr/bin/pg_dump"
        File.binwrite(command.fetch(command.index("--file") + 1), "database dump")
      end
      next [ { ContentLength: 13 }.to_json, "", success ] if command.include?("head-object")
      if command.each_cons(2).any? { |items| items == [ "s3", "ls" ] }
        next [ "2026-01-01 1 #{outdated}\n2026-01-02 1 #{recent}", "", success ]
      end

      [ "", "", success ]
    end

    job.perform

    dump = commands.find { |_, command| command.first == "/usr/bin/pg_dump" }.last
    upload = commands.find { |_, command| command.each_cons(2).any? { |items| items == [ "s3", "cp" ] } }.last
    key = File.basename(upload.fetch(-2))
    assert_equal [ "-U", "deploy", "--clean" ], dump.slice(1, 3)
    assert_equal [ "#{@backup_directory}/#{key}", "s3://test-bucket/#{key}" ], upload.last(2)
    assert commands.any? { |_, command| command.last(4) == [ "--bucket", "test-bucket", "--key", key ] }
    assert commands.any? { |_, command| command.last == "s3://test-bucket/#{outdated}" }
    refute commands.any? { |_, command| command.last == "s3://test-bucket/#{recent}" }
    assert_empty Dir.children(@backup_directory)

    storage_environment = commands.find { |_, command| command.first == "aws" }.first
    assert_equal "test_access_key", storage_environment.fetch("AWS_ACCESS_KEY_ID")
    assert_equal "test_secret_key", storage_environment.fetch("AWS_SECRET_ACCESS_KEY")
    assert_equal "standard", storage_environment.fetch("AWS_RETRY_MODE")
    assert_equal "6", storage_environment.fetch("AWS_MAX_ATTEMPTS")
    refute commands.flat_map { |_, command| command }.include?("test_secret_key")
  end

  def test_upload_failure_retains_dump_and_stops_remote_work
    job, commands = build_job do |_, command|
      if command.first == "/usr/bin/pg_dump"
        File.binwrite(command.fetch(command.index("--file") + 1), "recoverable dump")
        next [ "", "", success ]
      end
      next [ "", "connection closed during part 41", failure ] if command.each_cons(2).any? { |items| items == [ "s3", "cp" ] }

      [ "", "", success ]
    end

    error = assert_raises(DbBackupJob::BackupError) { job.perform }

    assert_includes error.message, "connection closed during part 41"
    assert_equal 1, completed_dumps.length
    assert_equal "recoverable dump", File.binread(completed_dumps.first)
    refute commands.any? { |_, command| command.include?("head-object") }
    refute commands.any? { |_, command| command.each_cons(2).any? { |items| items == [ "s3", "rm" ] } }
  end

  def test_retry_reuses_retained_dump
    upload_attempts = 0
    dump_attempts = 0
    job, = build_job do |_, command|
      if command.first == "/usr/bin/pg_dump"
        dump_attempts += 1
        File.binwrite(command.fetch(command.index("--file") + 1), "recoverable dump")
      end
      if command.each_cons(2).any? { |items| items == [ "s3", "cp" ] }
        upload_attempts += 1
        next [ "", "connection closed", failure ] if upload_attempts == 1
      end
      next [ { ContentLength: 16 }.to_json, "", success ] if command.include?("head-object")

      [ "", "", success ]
    end

    assert_raises(DbBackupJob::BackupError) { job.perform }
    job.perform

    assert_equal 1, dump_attempts
    assert_equal 2, upload_attempts
    assert_empty completed_dumps
  end

  def test_remote_size_mismatch_retains_dump
    job, commands = build_job do |_, command|
      if command.first == "/usr/bin/pg_dump"
        File.binwrite(command.fetch(command.index("--file") + 1), "database dump")
      end
      next [ { ContentLength: 1 }.to_json, "", success ] if command.include?("head-object")

      [ "", "", success ]
    end

    error = assert_raises(DbBackupJob::BackupError) { job.perform }

    assert_includes error.message, "expected 13"
    assert_equal 1, completed_dumps.length
    refute commands.any? { |_, command| command.each_cons(2).any? { |items| items == [ "s3", "rm" ] } }
  end

  def test_dump_failure_does_not_upload
    job, commands = build_job do |_, command|
      next [ "", "pg_dump failed", failure ] if command.first == "/usr/bin/pg_dump"

      [ "", "", success ]
    end

    error = assert_raises(DbBackupJob::BackupError) { job.perform }

    assert_includes error.message, "pg_dump failed"
    refute commands.any? { |_, command| command.first == "aws" }
    assert_empty completed_dumps
  end

  def test_new_scheduled_execution_preserves_a_new_dump_during_an_outage
    pending_path = File.join(@backup_directory, "#{db_name}_previous-job_#{1.day.ago.to_i}.sql")
    File.binwrite(pending_path, "previous dump")
    job, = build_job do |_, command|
      if command.first == "/usr/bin/pg_dump"
        File.binwrite(command.fetch(command.index("--file") + 1), "current dump")
        next [ "", "", success ]
      end
      next [ "", "storage unavailable", failure ] if command.each_cons(2).any? { |items| items == [ "s3", "cp" ] }

      [ "", "", success ]
    end

    assert_raises(DbBackupJob::BackupError) { job.perform }

    assert_equal [ "current dump", "previous dump" ], completed_dumps.map { |path| File.binread(path) }.sort
  end

  private

  def db_name = ActiveRecord::Base.connection_db_config.database

  def build_job(&response)
    commands = []
    job = DbBackupJob.new
    job.define_singleton_method(:capture) do |environment, command|
      commands << [ environment, command ]
      response.call(environment, command)
    end
    [ job, commands ]
  end

  def completed_dumps
    Dir[File.join(@backup_directory, "*.sql")]
  end

  def success = Status.new(successful: true, exitstatus: 0)
  def failure = Status.new(successful: false, exitstatus: 1)
end
