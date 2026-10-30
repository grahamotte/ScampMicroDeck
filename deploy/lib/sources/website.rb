module Sources
  class Website
    COMPATIBILITY_DATE = "2026-10-29"

    class << self
      attr_writer :checkout

      def droplet? = false

      def checkout = @checkout || File.join(Constants.local_root, "deploy", "tmp", "website")
      def root = File.join(checkout, "website")

      def wrangler_config
        {
          name: Constants.domain.tr(".", "-"),
          compatibility_date: COMPATIBILITY_DATE,
          assets: { directory: "./dist", not_found_handling: "404-page" },
          routes: Subdomains.website_domains.map { |domain| { pattern: domain, custom_domain: true } },
        }
      end

      def droplet_record?(record)
        Cloudflare.website_record?(record) && %w[A AAAA CNAME].include?(record[:type]) && !record[:proxied]
      end
    end
  end
end
