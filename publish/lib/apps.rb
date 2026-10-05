require "fileutils"
require "digest"
require "json"
require "openssl"
require "tempfile"

module Apps
  class << self
    attr_writer :root, :prepare_for_review, :submit_for_review, :tmp_root, :host_keychain_home

    def root = @root || File.join(Constants.local_root, "apps")
    def tmp_root = @tmp_root || File.join(Constants.local_root, "publish", "tmp", "apps")
    def config = @config ||= read_json(Constants.config_path).fetch(:apps)
    def version = config.fetch(:version)
    def build = config.fetch(:build)
    def skip_app_stores? = config.fetch(:skip_app_stores, false)
    def prepare_for_review? = @prepare_for_review != false
    def submit_for_review? = prepare_for_review? && @submit_for_review != false
    def export_options_path = File.join(root, "apple", "App", "Config", "ExportOptions.plist")

    def targets
      @targets ||= config
        .dig(:targets, :apple)
        .map { |name, target| target.merge(name:) }
    end

    def archive_path(target)
      File.join(tmp_root, version, "#{target.fetch(:name)}.xcarchive")
    end

    def export_path(target)
      File.join(tmp_root, version, "#{target.fetch(:name)}-export")
    end

    def revision_path(target)
      extension = target.fetch(:platform) == "MAC_OS" ? "zip" : "ipa"
      name = config.fetch(:name).gsub(/[^A-Za-z0-9]+/, "-").sub(/\A-/, "").sub(/-\z/, "")
      File.join(tmp_root, version, "revisions", "#{name}-#{target.fetch(:name)}-#{version}.#{extension}")
    end

    def revision_export_path(target)
      File.join(tmp_root, version, "#{target.fetch(:name)}-revision-export")
    end

    def main_root(root = Constants.local_root)
      git = File.join(root, ".git")
      return root unless File.file?(git)

      gitdir = File.read(git)[/\Agitdir: (.+)$/, 1]
      raise "Cannot locate the main checkout from #{git}" if gitdir.blank?

      File.dirname(File.expand_path(gitdir, root).sub(%r{/worktrees/[^/]+/?\z}, ""))
    end

    def mr_installed? = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { |directory| File.executable?(File.join(directory, "mr")) }

    def project_path(target)
      File.expand_path(target.fetch(:project), Constants.local_root)
    end

    def screenshot_path(screenshot)
      File.expand_path(screenshot.fetch(:path), Constants.local_root)
    end

    def review_attachment_path(attachment)
      File.expand_path(attachment.fetch(:path), Constants.local_root)
    end

    def private_key
      @private_key ||= OpenSSL::PKey.read(ENV.fetch("APPLE_KEY_SECRET_BASE64").unpack1("m0"))
    end

    def private_key_path
      return @private_key_file.path if @private_key_file.present?

      @private_key_file = Tempfile.new([ "app-store-connect", ".p8" ])
      @private_key_file.chmod(0600)
      @private_key_file.write(ENV.fetch("APPLE_KEY_SECRET_BASE64").unpack1("m0"))
      @private_key_file.close
      @private_key_file.path
    end

    def authentication_arguments
      [
        "-authenticationKeyPath",
        private_key_path,
        "-authenticationKeyID",
        ENV.fetch("APPLE_KEY_ID"),
        "-authenticationKeyIssuerID",
        ENV.fetch("APPLE_ISSUER_ID"),
      ]
    end

    def host_keychain
      @host_keychain ||= Keychain.new(
        home: @host_keychain_home || Dir.home,
        runner: ->(*arguments) { Cmd.local(Shellwords.join([ "security", *arguments ])) },
      )
    end

    def with_signing_certificate(name, prefix)
      with_signing_certificates([ [ name, prefix, "codesigning" ] ]) { |keychain| yield keychain }
    end

    def with_signing_certificates(certificates)
      keychain = File.join(tmp_root, "signing-#{Process.pid}.keychain-db")
      roots = "/System/Library/Keychains/SystemRootCertificates.keychain"
      host_keychain.protect do |saved|
        FileUtils.mkdir_p(tmp_root)
        password = "#{certificates.first.fetch(1)}_CERTIFICATE_PASSWORD"
        FileUtils.rm_f(keychain)
        Cmd.local("security create-keychain -p \"$#{password}\" #{Shellwords.escape(keychain)}")
        Cmd.local("security unlock-keychain -p \"$#{password}\" #{Shellwords.escape(keychain)}")
        Cmd.local(Shellwords.join([ "security", "list-keychains", "-d", "user", "-s", *[ keychain, *saved[:search], roots ].uniq ]))
        Cmd.local(Shellwords.join([ "security", "import", File.join(__dir__, "apps", "apple_certificate_authorities.pem"), "-k", keychain, "-f", "pemseq" ]))
        certificates.each do |name, prefix, policy|
          certificate_password = "#{prefix}_CERTIFICATE_PASSWORD"
          Tempfile.create([ "signing", ".p12" ]) do |certificate|
            certificate.binmode
            certificate.write(ENV.fetch("#{prefix}_CERTIFICATE_BASE64").unpack1("m0"))
            certificate.close
            Tempfile.create([ "signing", ".pem" ]) do |pem|
              Tempfile.create([ "signing-modern", ".p12" ]) do |modern|
                Cmd.local("/usr/bin/openssl pkcs12 -in #{Shellwords.escape(certificate.path)} -passin env:#{certificate_password} -nodes -out #{Shellwords.escape(pem.path)}")
                Cmd.local("/usr/bin/openssl pkcs12 -export -in #{Shellwords.escape(pem.path)} -out #{Shellwords.escape(modern.path)} -passout env:#{certificate_password}")
                Cmd.local("security import #{Shellwords.escape(modern.path)} -k #{Shellwords.escape(keychain)} -f pkcs12 -P \"$#{certificate_password}\" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild")
                arguments = [ "security", "find-identity", "-v" ]
                arguments.concat([ "-p", policy ]) if policy.present?
                identities = Cmd.local(Shellwords.join([ *arguments, keychain ]))
                raise "Missing #{name} identity" unless identities.include?(name)
              end
            end
          end
        end
        Cmd.local("security set-key-partition-list -S apple-tool:,apple: -s -k \"$#{password}\" #{Shellwords.escape(keychain)}")
        yield keychain
      ensure
        Cmd.local(Shellwords.join([ "security", "delete-keychain", keychain ])) rescue StandardError
      end
    end

    def reset
      @private_key_file&.unlink
      @config = nil
      @targets = nil
      @private_key = nil
      @private_key_file = nil
      @root = nil
      @prepare_for_review = nil
      @submit_for_review = nil
      @tmp_root = nil
      @host_keychain_home = nil
      @host_keychain = nil
    end

    private

    def read_json(path)
      JSON.parse(File.read(path), symbolize_names: true)
    rescue JSON::ParserError => error
      raise "Invalid JSON in #{path}: #{error.message}"
    end
  end
end
