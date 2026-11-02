require "json"

class Settings
  class << self
    def path = File.expand_path("../../config.json", __dir__)
    def all = @all ||= JSON.parse(File.read(path), symbolize_names: true)
    def root = File.expand_path("../..", __dir__)
    def rails_max_threads = all[:railsMaxThreads]

    def test_database(checkout = root)
      name = "#{all.fetch(:database)}_test"
      return name unless File.file?(File.join(checkout, ".git"))

      "#{name}_#{File.basename(checkout).downcase.gsub(/[^a-z0-9]+/, "_")}"[0, 56]
    end

    def stale_test_databases(databases, checkouts)
      current = checkouts.map { |x| test_database(x) }
      prefix = "#{all.fetch(:database)}_test_"

      databases
        .select { |x| x.start_with?(prefix) }
        .reject { |x| current.any? { |y| x.match?(/\A#{Regexp.escape(y)}(_\d+)?\z/) } }
    end

    def local_domain
      "#{ENV["LOCAL_DOMAIN"].presence || all.fetch(:domain).split(".").first.presence || all.fetch(:database)}.localhost"
    end

    def url(name)
      host(name, all.fetch(:domain))&.then { |x| "https://#{x}" }
    end

    def development_url(name)
      host(name, local_domain)&.then { |x| "https://#{x}" }
    end

    def origins
      all
        .fetch(:subdomains)
        .reject { |x| x.fetch(:source) == "backend" }
        .flat_map { |x| x.fetch(:subdomains) }
        .map { |x| "https://#{[ x.presence, all.fetch(:domain) ].compact.join(".")}" }
    end

    def development_origins
      [
        %r{\Ahttps://([a-z0-9-]+\.)*#{Regexp.escape(local_domain)}\z},
      ]
    end

    private

    def host(name, domain)
      subdomain = all.fetch(:subdomains).find { |x| x.fetch(:name) == name }
      return if subdomain.blank?

      [ subdomain.fetch(:subdomains).first.presence, domain ].compact.join(".")
    end
  end
end
