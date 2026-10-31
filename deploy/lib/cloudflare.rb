class Cloudflare
  REDIRECT_PHASE = "http_request_dynamic_redirect"

  class << self
    def zone_id(domain = Constants.domain)
      @zone_ids ||= {}
      @zone_ids[domain] ||= Req
        .call(
          url: "https://api.cloudflare.com/client/v4/zones",
          headers: headers,
          params: { name: domain },
          quiet: true,
        )
        .dig(:result)
        .find { |x| x[:name] == domain }
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

    def current_dns_records(domain = Constants.domain)
      return [] if zone_id(domain).blank?

      records = []
      page = 1
      loop do
        response = Req.call(
          url: "https://api.cloudflare.com/client/v4/zones/#{zone_id(domain)}/dns_records",
          headers: headers,
          params: { page: page, per_page: 100 },
          quiet: true,
        )
        records.concat(response.fetch(:result))
        return records if page >= response.dig(:result_info, :total_pages).to_i

        page += 1
      end
    rescue StandardError => e
      puts e.message
      []
    end

    def droplet_dns_records
      current_dns_records.reject { |x| website_record?(x) || mail_record?(x) }
    end

    def mail_record?(record)
      mail_dns_records.map { |x| fingerprint(x) }.include?(fingerprint(record))
    end

    def missing_mail_dns_records(domain = Constants.domain)
      missing_dns_records(mail_dns_records(domain), domain)
    end

    def missing_redirect_dns_records(domain)
      missing_dns_records(redirect_dns_records(domain), domain)
    end

    def missing_dns_records(records, domain = Constants.domain)
      current = current_dns_records(domain).map { |x| fingerprint(x, domain) }
      records.reject { |x| current.include?(fingerprint(x, domain)) }
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

    def delete_dns_record(record_id, domain = Constants.domain)
      Req.call(
        method: :delete,
        url: "https://api.cloudflare.com/client/v4/zones/#{zone_id(domain)}/dns_records/#{record_id}",
        headers: headers,
        quiet: true,
      )
    end

    def create_dns_record(record, domain = Constants.domain)
      Req.call(
        method: :post,
        url: "https://api.cloudflare.com/client/v4/zones/#{zone_id(domain)}/dns_records",
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

    def create_zone(domain = Constants.domain)
      Req.call(
        method: :post,
        url: "https://api.cloudflare.com/client/v4/zones",
        headers: headers,
        quiet: true,
        payload: { name: domain },
      )
    end

    def redirect_ruleset(domain)
      Req
        .call(
          url: "https://api.cloudflare.com/client/v4/zones/#{zone_id(domain)}/rulesets",
          headers: headers,
          quiet: true,
        )
        .fetch(:result)
        .find { |x| x[:kind] == "zone" && x[:phase] == REDIRECT_PHASE }
    end

    def redirect_rules(domain)
      ruleset = redirect_ruleset(domain)
      return [] if ruleset.blank?

      Req
        .call(
          url: "https://api.cloudflare.com/client/v4/zones/#{zone_id(domain)}/rulesets/#{ruleset[:id]}",
          headers: headers,
          quiet: true,
        )
        .dig(:result, :rules) || []
    end

    def redirect_rule_current?(domain)
      desired = redirect_rule(domain)
      redirect_rules(domain).any? do |rule|
        rule[:expression] == desired[:expression] &&
          rule[:action] == desired[:action] &&
          rule.dig(:action_parameters, :from_value) == desired.dig(:action_parameters, :from_value)
      end
    end

    def write_redirect_rule(domain)
      ruleset = redirect_ruleset(domain)
      if ruleset.blank?
        Req.call(
          method: :post,
          url: "https://api.cloudflare.com/client/v4/zones/#{zone_id(domain)}/rulesets",
          headers: headers,
          quiet: true,
          payload: {
            name: "Redirect #{domain} to #{Constants.domain}",
            kind: "zone",
            phase: REDIRECT_PHASE,
            rules: [ redirect_rule(domain) ],
          },
        )
      else
        Req.call(
          method: :put,
          url: "https://api.cloudflare.com/client/v4/zones/#{zone_id(domain)}/rulesets/#{ruleset[:id]}",
          headers: headers,
          quiet: true,
          payload: { rules: [ redirect_rule(domain) ] },
        )
      end
    end

    def redirect_rule(domain)
      {
        description: "Redirect #{domain} to #{Constants.domain}",
        expression: "(http.host in {\"#{domain}\" \"www.#{domain}\"})",
        action: "redirect",
        action_parameters: {
          from_value: {
            target_url: { expression: "concat(\"https://#{Constants.domain}\", http.request.uri.path)" },
            status_code: 301,
            preserve_query_string: true,
          },
        },
      }
    end

    def redirect_dns_records(domain)
      [ domain, "www.#{domain}" ].map do |name|
        {
          type: "A",
          name: name,
          content: "192.0.2.1",
          proxied: true,
          ttl: 1,
        }
      end
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
      end
    end

    def mail_dns_records(domain = Constants.domain)
      [
        {
          type: "MX",
          name: domain,
          priority: 10,
          content: "in1-smtp.messagingengine.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "MX",
          name: domain,
          priority: 20,
          content: "in2-smtp.messagingengine.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "CNAME",
          name: "fm1._domainkey.#{domain}",
          content: "fm1.#{domain}.dkim.fmhosted.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "CNAME",
          name: "fm2._domainkey.#{domain}",
          content: "fm2.#{domain}.dkim.fmhosted.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "CNAME",
          name: "fm3._domainkey.#{domain}",
          content: "fm3.#{domain}.dkim.fmhosted.com",
          proxied: false,
          ttl: 1,
        },
        {
          type: "TXT",
          name: domain,
          content: "v=spf1 include:spf.messagingengine.com ?all",
          proxied: false,
          ttl: 1,
        },
      ]
    end

    def fingerprint(record, domain = Constants.domain)
      [
        record[:name].end_with?(domain) ? record[:name] : "#{record[:name]}.#{domain}",
        record[:type],
        record[:content],
      ].join(" :: ")
    end
  end
end
