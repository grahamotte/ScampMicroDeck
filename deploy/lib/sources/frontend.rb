module Sources
  class Frontend
    class << self
      def droplet? = true

      def dist(subdomain)
        File.join(Constants.remote_root, "frontend", "dist", subdomain.fetch(:name))
      end

      def build(subdomain)
        Cmd.ssh("cd #{Constants.remote_root}/frontend; set -a; source ../.env; VITE_SUBDOMAIN=#{subdomain.fetch(:name)} mise exec -- pnpm exec vite build")
      end

      def locations(subdomain)
        <<~TEXT
          root #{dist(subdomain)};
          index index.html;

          location / {
            #{headers(subdomain)}
            try_files $uri /index.html;
          }

          location /assets/ {
            expires max;
            add_header Cache-Control "public, max-age=31536000, immutable";
            #{headers(subdomain)}
          }

          location ~ ^/(apple-touch-icon[^/]*\\.png|favicon[^/]*\\.(ico|png))$ {
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            #{headers(subdomain)}
            try_files $uri =404;
          }

          #{backend_locations(subdomain)}
        TEXT
      end

      def headers(subdomain)
        <<~TEXT
          add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header Referrer-Policy "strict-origin-when-cross-origin" always;
          add_header Content-Security-Policy "#{content_security_policy(subdomain)}" always;
        TEXT
      end

      def content_security_policy(subdomain)
        subdomain.fetch(:contentSecurityPolicy) do
          [
            "default-src 'self'",
            "script-src 'self'",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob: https:",
            "font-src 'self' data:",
            "connect-src 'self' https://#{Constants.domain} https://*.#{Constants.domain}",
            "object-src 'none'",
            "base-uri 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
          ].join("; ")
        end
      end

      def backend_locations(subdomain)
        subdomain.fetch(:backendPaths, []).map { |path| Sources::Backend.proxy_location(path) }.join("\n")
      end
    end
  end
end
