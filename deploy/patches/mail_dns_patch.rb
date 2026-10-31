class MailDnsPatch < BasePatch
  class << self
    def needed?
      Constants.mail_domains.any? do |domain|
        Cloudflare.zone_id(domain).blank? || Cloudflare.missing_mail_dns_records(domain).present?
      end
    end

    def apply
      Constants.mail_domains.each do |domain|
        if Cloudflare.zone_id(domain).blank?
          Cloudflare.create_zone(domain)
        end

        Cloudflare.missing_mail_dns_records(domain).each do |record|
          Cloudflare.create_dns_record(record, domain)
        end
      end
    end
  end
end
