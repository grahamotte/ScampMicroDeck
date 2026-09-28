require "digest"
require "fileutils"
require "json"
require "open3"
require "securerandom"
require "socket"
require "tmpdir"

class SpawnShell
  def capture(*command)
    stdout, stderr, status = Open3.capture3(*command)
    raise "#{command.join(" ")} failed: #{stderr.strip}" unless status.success?

    stdout
  end

  def run(*command, chdir: nil)
    success = chdir ? system(*command, chdir: chdir) : system(*command)
    return if success

    raise "#{command.join(" ")} failed"
  end
end

class SpawnCredentials
  def initialize(shell: SpawnShell.new, random: SecureRandom)
    @shell = shell
    @random = random
  end

  def call
    Dir.mktmpdir("spawn-keygen") do |directory|
      private_key_path = File.join(directory, "id_rsa")
      comment = "deploy@#{Socket.gethostname.split(".").first}"
      @shell.run(
        "ssh-keygen",
        "-t",
        "rsa",
        "-b",
        "4096",
        "-m",
        "PEM",
        "-N",
        "",
        "-C",
        comment,
        "-f",
        private_key_path,
        "-q",
      )

      public_key = File.read("#{private_key_path}.pub").strip

      {
        "DEPLOY_USER" => "deploy",
        "DEPLOY_PASSWORD" => @random.hex(16),
        "DEPLOY_SSH_KEY_PUB" => public_key,
        "DEPLOY_SSH_KEY_FINGERPRINT" => fingerprint(public_key),
        "DEPLOY_SSH_KEY" => File.read(private_key_path).strip,
        "JWT_SECRET" => @random.hex(64),
        "SECRET_KEY_BASE" => @random.hex(64),
        "CRYPT_KEY" => @random.hex(64),
      }
    end
  end

  private

  def fingerprint(public_key)
    key = public_key.split.fetch(1).unpack1("m0")
    Digest::MD5.hexdigest(key).scan(/../).join(":")
  end
end

class Spawner
  ENVIRONMENTS = %w[development production].freeze
  ENVIRONMENT_KEYS = %w[NODE_ENV RAILS_ENV].freeze
  REQUIRED_KEYS = (
    ENVIRONMENT_KEYS +
    %w[
      CRYPT_KEY
      DEPLOY_PASSWORD
      DEPLOY_SSH_KEY
      DEPLOY_SSH_KEY_FINGERPRINT
      DEPLOY_SSH_KEY_PUB
      DEPLOY_USER
      JWT_SECRET
      SECRET_KEY_BASE
    ]
  ).freeze

  def initialize(app_name, shell: SpawnShell.new, credentials: SpawnCredentials.new, output: $stdout)
    @app_name = app_name
    @shell = shell
    @credentials = credentials
    @output = output
  end

  def call
    validate_app_name
    source_repo = @shell.capture("git", "rev-parse", "--show-toplevel").strip
    target_dir = File.join(File.dirname(source_repo), @app_name)
    raise "Path already exists: #{target_dir}" if File.exist?(target_dir)

    @output.puts "Cloning #{source_repo} to #{target_dir}..."
    @shell.run("git", "clone", source_repo, target_dir)
    create_environment_files(target_dir)
    repo = write_config(target_dir)
    @shell.run("git", "remote", "set-url", "origin", repo, chdir: target_dir)
    @shell.run("git", "config", "remote.origin.gh-resolved", "base", chdir: target_dir)

    @output.puts "New app created at #{target_dir}"
    @output.puts "Create #{repo} on GitHub, then run 'git push -u origin master' there."
    @output.puts "Run 'mise merge' there to merge updates from Code Moto."
    target_dir
  end

  private

  def validate_app_name
    labels = @app_name.split(".")
    valid_labels = labels.all? { |label| label.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\z/) }
    valid_tld = labels.length > 1 && labels.last.match?(/\A[a-zA-Z]{2,63}\z/)
    return if valid_labels && valid_tld && @app_name.length <= 253

    raise "App name must be a website domain ending in a TLD, such as example.com"
  end

  def create_environment_files(target_dir)
    template = File.read(File.join(target_dir, ".env.default"))

    ENVIRONMENTS.each do |environment|
      overrides = ENVIRONMENT_KEYS.to_h { |key| [ key, environment ] }.merge(@credentials.call)
      missing_keys = REQUIRED_KEYS - overrides.keys
      raise "Missing environment values: #{missing_keys.join(", ")}" unless missing_keys.length.zero?

      path = File.join(target_dir, ".env.#{environment}")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
        file.write(render(template, overrides))
      end
      @output.puts "Created #{path}"
    end
  end

  def write_config(target_dir)
    path = File.join(target_dir, "config.json")
    config = JSON.parse(File.read(path))
    repo = transformed_repo(config.fetch("githubRepo"))
    config.merge!(
      "domain" => @app_name,
      "githubRepo" => repo,
      "database" => database_name,
      "secrets" => config.fetch("secrets", {}).transform_values { "" },
    )
    File.write(path, "#{JSON.pretty_generate(config)}\n")
    @output.puts "Updated #{path}"
    repo
  end

  def transformed_repo(repo)
    repo.sub(%r{[^/:]+(?=\.git\z)}, @app_name)
  end

  def database_name
    @app_name.split(".").first.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  def render(template, overrides)
    found = []
    rendered = records(template).map do |key, _raw_value, record|
      next record unless overrides.key?(key)

      found << key
      "#{key}=#{quoted(overrides.fetch(key))}\n"
    end.join
    missing_keys = overrides.keys - found
    unless missing_keys.length.zero?
      raise "Template is missing environment values: #{missing_keys.join(", ")}"
    end

    rendered
  end

  def records(template)
    lines = template.lines
    records = []
    index = 0

    while index < lines.length
      line = lines[index]
      match = line.match(/\A([A-Z][A-Z0-9_]*)=(.*)/)

      unless match
        records << [ nil, nil, line ]
        index += 1
        next
      end

      key = match[1]
      raw_value = match[2]
      record = line
      if raw_value.start_with?("\"") && !raw_value.chomp.end_with?("\"")
        loop do
          index += 1
          raise "Unterminated quoted value for #{key}" if index >= lines.length

          record += lines[index]
          raw_value += lines[index]
          break if lines[index].chomp.end_with?("\"")
        end
      end
      records << [ key, raw_value.chomp, record ]
      index += 1
    end

    records
  end

  def quoted(value)
    escaped = value.gsub(/[\\\"$`]/) { |character| "\\#{character}" }
    "\"#{escaped}\""
  end
end
