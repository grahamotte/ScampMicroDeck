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
            try_files $uri /index.html;
          }

          location /assets/ {
            expires max;
            add_header Cache-Control "public, max-age=31536000, immutable";
          }
        TEXT
      end
    end
  end
end
