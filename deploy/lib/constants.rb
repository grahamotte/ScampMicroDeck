class Constants
  class << self
    attr_writer :config_path, :local_env_path

    def local_root = File.dirname(File.dirname(File.dirname(__FILE__)))
    def config_path = @config_path || File.join(local_root, "config.json")
    def config = @config ||= JSON.parse(File.read(config_path), symbolize_names: true)
    def remote_root = "/var/www/#{domain}"
    def remote_home_dir = "/home/#{deploy_user}"
    def local_git_dir = File.join(local_root, "deploy", "tmp", "#{domain}.git")
    def remote_git_dir = "/home/#{deploy_user}/#{domain}.git"
    def deploy_user = ENV.fetch("DEPLOY_USER")
    def app_user = "app"
    def app_home_dir = "/home/#{app_user}"
    def remote_mise_data_dir = File.join(remote_home_dir, ".local", "share", "mise")
    def app_writable_dirs = %w[tmp storage log].map { |dir| File.join(remote_root, "backend", dir) }
    def deploy_password = ENV.fetch("DEPLOY_PASSWORD")
    def ssh_key_fingerprint = ENV.fetch("DEPLOY_SSH_KEY_FINGERPRINT")
    def digital_ocean_token = ENV.fetch("DIGITAL_OCEAN_TOKEN")
    def cloudflare_token = ENV.fetch("CLOUDFLARE_TOKEN")
    def domain
      domain = config.fetch(:domain)
      raise "config.json domain is required to deploy" if domain.blank?

      domain
    end
    def redirect_domains = config.fetch(:redirectDomains, [])
    def mail_domains = [ domain, *redirect_domains ]
    def resend_domains = config.fetch(:resendDomains, [])
    def deploy_ref = ENV["DEPLOY_REF"].blank? ? "origin/master" : ENV["DEPLOY_REF"]
    def instance_region = config.dig(:instance, :region)
    def instance_size = config.dig(:instance, :size)
    def remote_env_path = File.join(remote_root, ".env")
    def remote_env_prod_path = File.join(remote_root, ".env.production")
    def local_env_path = @local_env_path || File.join(local_root, ".env.production")
    def operator_only_env_keys = config.fetch(:operatorOnlyEnvKeys)
    def server_env
      File.read(local_env_path).lines.reject do |line|
        key = line[/\A\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=/, 1]
        key.present? && operator_only_env_keys.any? { |pattern| File.fnmatch?(pattern, key) }
      end.join
    end
    def db_name = "#{config.fetch(:database)}_production"
    def backup_access_key_id = ENV.fetch("BACKUP_ACCESS_KEY_ID")
    def backup_secret_access_key = ENV.fetch("BACKUP_SECRET_ACCESS_KEY")
    def backup_endpoint = ENV.fetch("BACKUP_ENDPOINT")
    def backup_bucket = ENV.fetch("BACKUP_BUCKET")
    def github_repo = config.fetch(:githubRepo, "")
    def ssh_key = ENV.fetch("DEPLOY_SSH_KEY_BASE64").unpack1("m0")
    def ssh_key_pub = ENV.fetch("DEPLOY_SSH_KEY_PUB")
    def ssh_key_path
      @ssh_key_path ||= begin
        path = File.join(local_root, "deploy", "tmp", "id_rsa")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, ssh_key, perm: 0600)
        File.chmod(0600, path)
        path
      end
    end
  end
end
