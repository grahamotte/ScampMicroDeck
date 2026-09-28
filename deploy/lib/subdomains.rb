class Subdomains
  class << self
    def all
      @all ||= Constants.config.fetch(:subdomains)
    end

    def domains(subdomain = nil)
      (subdomain.present? ? subdomain.fetch(:subdomains) : all.flat_map { |x| x.fetch(:subdomains) })
        .map { |x| x.present? ? "#{x}.#{Constants.domain}" : Constants.domain }
    end

    def frontends
      all.select { |subdomain| subdomain[:directory].present? }
    end

    def dist(subdomain)
      File.join(Constants.remote_root, "frontend", "dist", subdomain.fetch(:name))
    end
  end
end
