class Cloudflare
  class << self
    def zone_id
      @zone_id ||= Req
        .call(
          url: "https://api.cloudflare.com/client/v4/zones",
          headers: headers,
          params: { name: Constants.domain },
          quiet: true,
        )
        .dig(:result)
        .find { |x| x[:name] == Constants.domain }
        .dig(:id)
    rescue StandardError => e
      puts e.message
      nil
    end

    def account_id
      @account_id ||= Req
        .call(
          url: "https://api.cloudflare.com/client/v4/zones",
          headers: headers,
          params: { name: Constants.domain },
          quiet: true,
        )
        .dig(:result)
        .find { |x| x[:name] == Constants.domain }
        .dig(:account, :id)
    end

    def current_dns_records
      return [] if zone_id.blank?

      Req
        .call(
          url: "https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records",
          headers: headers,
          quiet: true,
        )
        .fetch(:result)
    rescue StandardError => e
      puts e.message
      []
    end

    def droplet_dns_records
      current_dns_records.reject { |x| website_record?(x) }
    end

    def website_record?(record)
      Subdomains.website_domains.include?(record[:name]) && !%w[MX TXT].include?(record[:type])
    end

    def headers
      {
        Authorization: "Bearer #{Constants.cloudflare_token}",
        "Content-Type": "application/json",
      }
    end

    def delete_dns_record(record_id)
      Req.call(
        method: :delete,
        url: "https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records/#{record_id}",
        headers: headers,
        quiet: true,
      )
    end

    def create_dns_record(record)
      Req.call(
        method: :post,
        url: "https://api.cloudflare.com/client/v4/zones/#{zone_id}/dns_records",
        headers: headers,
        quiet: true,
        payload: record,
      )
    end

    def enable_always_use_https
      Req.call(
        method: :patch,
        url: "https://api.cloudflare.com/client/v4/zones/#{zone_id}/settings/always_use_https",
        headers: headers,
        quiet: true,
        payload: { value: "on" },
      )
    end

    def create_zone
      Req.call(
        method: :post,
        url: "https://api.cloudflare.com/client/v4/zones",
        headers: headers,
        quiet: true,
        payload: { name: Constants.domain },
      )
    end

    def current_records_are_desired?
      return false if zone_id.blank?

      droplet_dns_records.map { |x| fingerprint(x) }.sort == desired_dns_records.map { |x| fingerprint(x) }.sort
    end

    def desired_dns_records
      Subdomains.domains.map do |domain|
        {
          type: "A",
          name: domain,
          content: Instance.ip,
          proxied: false,
          ttl: 1,
        }
      end + [
        {
          type: "MX",
          name: Constants.domain,
          priority: 10,
          content: "in1-smtp.messagingengine.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "MX",
          name: Constants.domain,
          priority: 20,
          content: "in2-smtp.messagingengine.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "CNAME",
          name: "fm1._domainkey.#{Constants.domain}",
          content: "fm1.#{Constants.domain}.dkim.fmhosted.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "CNAME",
          name: "fm2._domainkey.#{Constants.domain}",
          content: "fm2.#{Constants.domain}.dkim.fmhosted.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "CNAME",
          name: "fm3._domainkey.#{Constants.domain}",
          content: "fm3.#{Constants.domain}.dkim.fmhosted.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "TXT",
          name: Constants.domain,
          content: "v=spf1 include:spf.messagingengine.com ?all",
          proxied: false,
          ttl: 1,
        },
      ]
    end

    def fingerprint(record)
      [
        record[:name].end_with?(Constants.domain) ? record[:name] : "#{record[:name]}.#{Constants.domain}",
        record[:type],
        record[:content],
      ].join(" :: ")
    end
  end
end
