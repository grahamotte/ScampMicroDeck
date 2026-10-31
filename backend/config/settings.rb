require "json"

class Settings
  class << self
    def path = File.expand_path("../../config.json", __dir__)
    def all = @all ||= JSON.parse(File.read(path), symbolize_names: true)

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
        %r{\Ahttps://[a-z0-9-]+\.trycloudflare\.com\z},
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
