class Subdomains
  class << self
    def sources
      {
        "website" => Sources::Website,
        "frontend" => Sources::Frontend,
        "backend" => Sources::Backend,
      }
    end

    def all
      @all ||= Constants.config.fetch(:subdomains).each do |subdomain|
        raise "config.json subdomain #{subdomain[:name]} has unknown source #{subdomain[:source].inspect}" unless sources.key?(subdomain[:source])
      end
    end

    def source(subdomain)
      sources.fetch(subdomain.fetch(:source))
    end

    def from(name)
      all.select { |subdomain| subdomain.fetch(:source) == name }
    end

    def droplet
      all.select { |subdomain| source(subdomain).droplet? }
    end

    def droplet?
      droplet.present?
    end

    def websites
      from("website")
    end

    def frontends
      from("frontend")
    end

    def domains(subdomain = nil)
      (subdomain.present? ? subdomain.fetch(:subdomains) : droplet.flat_map { |x| x.fetch(:subdomains) })
        .map { |x| x.present? ? "#{x}.#{Constants.domain}" : Constants.domain }
    end

    def website_domains
      websites.flat_map { |subdomain| domains(subdomain) }
    end

    def url(name)
      "https://#{domains(all.find { |subdomain| subdomain.fetch(:name) == name }).first}"
    end
  end
end
