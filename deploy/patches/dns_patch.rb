class DnsPatch < BasePatch
  class << self
    def needed?
      return true if Cloudflare.zone_id.blank?
      !Cloudflare.current_records_are_desired?
    end

    def apply
      if Cloudflare.zone_id.blank?
        Cloudflare.create_zone
      end

      Cloudflare.droplet_dns_records.each do |record|
        Cloudflare.delete_dns_record(record[:id])
      end

      Cloudflare.desired_dns_records.each do |record|
        Cloudflare.create_dns_record(record)
      end
    end
  end
end
