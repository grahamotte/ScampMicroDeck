require_relative "test_helper"
require "stringio"

class SpawnTestShell
  attr_reader :commands

  def initialize(source_repo)
    @source_repo = source_repo
    @commands = []
  end

  def capture(*command)
    @commands << [ command, nil ]
    "#{@source_repo}\n"
  end

  def run(*command, chdir: nil)
    @commands << [ command, chdir ]
    FileUtils.cp_r("#{@source_repo}/.", command.fetch(3)) if command.first(2) == %w[git clone]
  end
end

class SpawnTestCredentials
  attr_reader :calls

  def initialize
    @calls = 0
  end

  def call
    @calls += 1
    {
      "DEPLOY_USER" => "deploy",
      "DEPLOY_PASSWORD" => "password-#{@calls}",
      "DEPLOY_SSH_KEY_PUB" => "public-key-#{@calls}",
      "DEPLOY_SSH_KEY_FINGERPRINT" => "fingerprint-#{@calls}",
      "DEPLOY_SSH_KEY" => "private-key-#{@calls}\nsecond-line",
      "JWT_SECRET" => "jwt-#{@calls}",
      "SECRET_KEY_BASE" => "secret-#{@calls}",
      "CRYPT_KEY" => "crypt-#{@calls}",
    }
  end
end

class SpawnCredentialsTestShell
  attr_reader :command

  def run(*command, chdir: nil)
    @command = command
    private_key_path = command.fetch(command.index("-f") + 1)
    File.write(private_key_path, "private-key\n")
    File.write("#{private_key_path}.pub", "ssh-rsa #{[ "public-key" ].pack("m0")} deploy@test\n")
  end
end

class SpawnCredentialsTestRandom
  def initialize
    @value = 0
  end

  def hex(bytes)
    @value += 1
    @value.to_s * (bytes * 2)
  end
end

class SpawnCredentialsTest < Minitest::Test
  def test_generates_deploy_and_application_credentials
    shell = SpawnCredentialsTestShell.new
    credentials = SpawnCredentials.new(
      shell: shell,
      random: SpawnCredentialsTestRandom.new,
    ).call

    assert_equal "deploy", credentials.fetch("DEPLOY_USER")
    assert_equal "1" * 32, credentials.fetch("DEPLOY_PASSWORD")
    assert_equal "2" * 128, credentials.fetch("JWT_SECRET")
    assert_equal "3" * 128, credentials.fetch("SECRET_KEY_BASE")
    assert_equal "4" * 128, credentials.fetch("CRYPT_KEY")
    assert_equal "ssh-rsa #{[ "public-key" ].pack("m0")} deploy@test", credentials.fetch("DEPLOY_SSH_KEY_PUB")
    assert_equal Digest::MD5.hexdigest("public-key").scan(/../).join(":"), credentials.fetch("DEPLOY_SSH_KEY_FINGERPRINT")
    assert_equal "private-key", credentials.fetch("DEPLOY_SSH_KEY")
    assert_includes shell.command, "4096"
    assert_includes shell.command, "PEM"
  end
end

class SpawnerTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir
    @source_repo = File.join(@directory, "codemoto.org")
    FileUtils.mkdir_p(@source_repo)
    FileUtils.cp(File.expand_path("../../.env.default", __dir__), @source_repo)
    FileUtils.cp(File.expand_path("../../config.json", __dir__), @source_repo)
    @shell = SpawnTestShell.new(@source_repo)
    @credentials = SpawnTestCredentials.new
    @output = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_spawns_repo_with_app_origin_and_creates_distinct_environment_files
    target_dir = Spawner.new(
      "new-app.net",
      shell: @shell,
      credentials: @credentials,
      output: @output,
    ).call

    development = environment(File.join(target_dir, ".env.development"))
    production = environment(File.join(target_dir, ".env.production"))

    config = JSON.parse(File.read(File.join(target_dir, "config.json")))
    source_config = JSON.parse(File.read(File.join(@source_repo, "config.json")))

    assert_equal 2, @credentials.calls
    assert_equal "development", development.fetch("RAILS_ENV")
    assert_equal "production", production.fetch("RAILS_ENV")
    assert_equal "development", development.fetch("NODE_ENV")
    assert_equal "production", production.fetch("NODE_ENV")
    assert_equal "git@github.com:grahamotte/new-app.net.git", config.fetch("githubRepo")
    assert_equal "new-app.net", config.fetch("domain")
    assert_equal "new_app", config.fetch("database")
    refute config.key?("secrets")
    assert_equal source_config.fetch("instance"), config.fetch("instance")
    assert_equal source_config.fetch("subdomains"), config.fetch("subdomains")
    assert_includes File.read(File.join(target_dir, ".env.production")), "OPENROUTER_TOKEN=xxx\n"
    assert_equal "password-1", development.fetch("DEPLOY_PASSWORD")
    assert_equal "password-2", production.fetch("DEPLOY_PASSWORD")
    assert_equal "private-key-1\nsecond-line", development.fetch("DEPLOY_SSH_KEY")
    refute_equal development.fetch("JWT_SECRET"), production.fetch("JWT_SECRET")
    assert_equal "public-key-2", production.fetch("DEPLOY_SSH_KEY_PUB")
    assert_equal "fingerprint-2", production.fetch("DEPLOY_SSH_KEY_FINGERPRINT")
    assert_equal "deploy", production.fetch("DEPLOY_USER")
    refute config.key?("deploy")
    assert_includes @shell.commands, [ %w[git remote set-url origin git@github.com:grahamotte/new-app.net.git], target_dir ]
    assert_includes @shell.commands, [ %w[git config remote.origin.gh-resolved base], target_dir ]
    assert_includes @output.string, "Create git@github.com:grahamotte/new-app.net.git on GitHub, then run 'git push -u origin master' there."
    assert_includes @output.string, "Run 'mise merge' there to merge updates from Code Moto."
    assert_includes @output.string, "Register it in Mr. Moto's config.json projects with its 1Password secrets references."
    assert_equal 0600, File.stat(File.join(target_dir, ".env.production")).mode & 0777
  end

  def test_rejects_an_app_name_without_a_tld
    error = assert_raises(RuntimeError) { Spawner.new("new-app", shell: @shell, credentials: @credentials, output: @output).call }

    assert_match(/ending in a TLD/, error.message)
    assert_empty @shell.commands
  end

  def test_rejects_an_invalid_domain
    %w[../bad example. -example.com example-.com example.c].each do |domain|
      assert_raises(RuntimeError) { Spawner.new(domain, shell: @shell, credentials: @credentials, output: @output).call }
    end

    assert_empty @shell.commands
  end

  private

  def environment(path)
    values = {}
    key = nil

    File.foreach(path, chomp: true) do |line|
      if (match = line.match(/\A([A-Z][A-Z0-9_]*)="(.*)\z/))
        key = match[1]
        values[key] = match[2]
        key = nil if match[2].end_with?("\"")
        values[match[1]] = match[2][0..-2] if match[2].end_with?("\"")
      elsif key
        if line.end_with?("\"")
          values[key] += "\n#{line[0..-2]}"
          key = nil
        else
          values[key] += "\n#{line}"
        end
      end
    end

    values
  end
end
