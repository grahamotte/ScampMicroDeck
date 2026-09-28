require "fileutils"
require "json"
require "open3"

class DbBackupJob < ApplicationJob
  class BackupError < StandardError; end

  schedule "every 1 day"

  retry_on BackupError, wait: :polynomially_longer, attempts: 5

  def perform
    prepare_backup_directory
    create_dump_if_needed
    completed_dump_paths.each { |path| upload_and_verify(path) }
    prune_remote_backups
  end

  private

  def prepare_backup_directory
    FileUtils.mkdir_p(backup_directory, mode: 0o700)
    File.chmod(0o700, backup_directory)
    remove_stale_partial_dumps
  end

  def create_dump_if_needed
    return if current_dump_path.present?

    timestamp = Time.now.to_i
    path = File.join(backup_directory, "#{db_name}_#{job_id}_#{timestamp}.sql")
    partial_path = File.join(backup_directory, "#{db_name}_#{job_id}.partial")
    File.delete(partial_path) if File.exist?(partial_path)
    File.open(partial_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { }

    run_command([
      "/usr/bin/pg_dump",
      "-U",
      deploy_user,
      "--clean",
      "--file",
      partial_path,
      db_name,
    ])
    validate_local_dump(partial_path)
    File.rename(partial_path, path)
  rescue BackupError
    raise
  rescue StandardError => error
    raise BackupError, "Could not create local backup: #{error.message}"
  end

  def upload_and_verify(path)
    key = File.basename(path)
    local_size = validate_local_dump(path)

    run_storage_command([
      "aws",
      "--endpoint-url",
      endpoint,
      "s3",
      "cp",
      "--no-progress",
      path,
      "s3://#{bucket}/#{key}",
    ])

    head_output = run_storage_command([
      "aws",
      "--endpoint-url",
      endpoint,
      "s3api",
      "head-object",
      "--bucket",
      bucket,
      "--key",
      key,
    ])
    remote_size = JSON.parse(head_output).fetch("ContentLength").to_i
    unless remote_size == local_size
      raise BackupError, "Backup #{key} has #{remote_size} remote bytes; expected #{local_size}"
    end

    File.delete(path)
    Rails.logger.info("Verified backup #{key} (#{remote_size} bytes)")
  rescue JSON::ParserError, KeyError => error
    raise BackupError, "Could not verify backup #{key}: #{error.message}"
  end

  def prune_remote_backups
    keep_backups_for = 60.days
    all_backups = run_storage_command([
      "aws",
      "--endpoint-url",
      endpoint,
      "s3",
      "ls",
      "s3://#{bucket}/#{db_name}_",
    ])
      .split("\n")
      .map { |line| line.split.last }
      .select { |key| key.start_with?("#{db_name}_") && key.end_with?(".sql") }
    outdated_backups = all_backups.select do |key|
      key.rpartition("_").last.delete_suffix(".sql").to_i < keep_backups_for.ago.to_i
    end

    outdated_backups.each do |key|
      run_storage_command([
        "aws",
        "--endpoint-url",
        endpoint,
        "s3",
        "rm",
        "s3://#{bucket}/#{key}",
      ])
    end
  rescue BackupError => error
    Rails.logger.error("Backup retention cleanup failed: #{error.message}")
  end

  def validate_local_dump(path)
    size = File.size(path)
    raise BackupError, "Local backup #{File.basename(path)} is empty" unless size.positive?

    size
  rescue Errno::ENOENT
    raise BackupError, "Local backup #{File.basename(path)} is missing"
  end

  def run_storage_command(command)
    run_command(command, environment: storage_environment)
  end

  def run_command(command, environment: {})
    stdout, stderr, status = capture(environment, command)
    return stdout if status.success?

    detail = stderr.strip.presence || stdout.strip.presence || "unknown error"
    raise BackupError, "#{command.first} failed with exit status #{status.exitstatus}: #{detail}"
  end

  def capture(environment, command)
    Open3.capture3(environment, *command)
  end

  def completed_dump_paths
    Dir.children(backup_directory)
      .select { |name| name.start_with?("#{db_name}_") && name.end_with?(".sql") }
      .map { |name| File.join(backup_directory, name) }
      .select { |path| File.file?(path) }
      .sort_by { |path| [ File.mtime(path), path ] }
  end

  def current_dump_path
    prefix = "#{db_name}_#{job_id}_"
    completed_dump_paths.find { |path| File.basename(path).start_with?(prefix) }
  end

  def remove_stale_partial_dumps
    Dir.children(backup_directory)
      .select { |name| name.start_with?("#{db_name}_") && name.end_with?(".partial") }
      .map { |name| File.join(backup_directory, name) }
      .select { |path| File.mtime(path) < 1.day.ago }
      .each { |path| File.delete(path) }
  end

  def storage_environment
    {
      "AWS_ACCESS_KEY_ID" => ENV.fetch("BACKUP_ACCESS_KEY_ID"),
      "AWS_SECRET_ACCESS_KEY" => ENV.fetch("BACKUP_SECRET_ACCESS_KEY"),
      "AWS_REQUEST_CHECKSUM_CALCULATION" => "WHEN_REQUIRED",
      "AWS_RESPONSE_CHECKSUM_VALIDATION" => "WHEN_REQUIRED",
      "AWS_RETRY_MODE" => "standard",
      "AWS_MAX_ATTEMPTS" => "6",
    }
  end

  def db_name = ActiveRecord::Base.connection_db_config.database
  def deploy_user = ENV.fetch("DEPLOY_USER")
  def endpoint = ENV.fetch("BACKUP_ENDPOINT")
  def bucket = ENV.fetch("BACKUP_BUCKET")

  def backup_directory
    ENV.fetch("BACKUP_LOCAL_DIR", File.join("/home", deploy_user, "backups"))
  end
end
