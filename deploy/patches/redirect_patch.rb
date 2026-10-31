class RedirectPatch < BasePatch
  class << self
    def needed?
      Constants.redirect_domains.any? do |domain|
        Cloudflare.zone_id(domain).blank? ||
          Cloudflare.missing_redirect_dns_records(domain).present? ||
          !Cloudflare.redirect_rule_current?(domain)
      end
    end

    def apply
      Constants.redirect_domains.each do |domain|
        if Cloudflare.zone_id(domain).blank?
          Cloudflare.create_zone(domain)
        end

        Cloudflare.missing_redirect_dns_records(domain).each do |record|
          Cloudflare.create_dns_record(record, domain)
        end

        Cloudflare.write_redirect_rule(domain)
      end
    end
  end
end
