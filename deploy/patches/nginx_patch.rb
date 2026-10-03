class NginxPatch < BasePatch
  class << self
    def always
      Instance.install_package("nginx")
      Cmd.ssh_write('/etc/nginx/nginx.conf', nginx_config, sudo: true)
      Instance.restart_service("nginx")
    end

    private

    def nginx_config
      <<~TEXT
        worker_processes 2;

        events {
          worker_connections 1024;
        }

        http {
          types_hash_max_size 4096;
          server_names_hash_bucket_size 128;
          include mime.types;
          default_type application/octet-stream;
          sendfile on;
          keepalive_timeout 65;
          gzip on;
          gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;
          gzip_vary on;

          server {
            listen 127.0.0.1:80;
            listen [::1]:80;

            location /nginx_status {
              stub_status on;
              access_log off;
              allow 127.0.0.1;
              deny all;
            }
          }

          server {
            listen 80;
            listen [::]:80;
            server_name #{Subdomains.domains.join(" ")};
            return 301 https://$host$request_uri;
          }

          #{subdomain_servers}
        }
      TEXT
    end

    def subdomain_servers
      Subdomains.all.map do |subdomain|
        <<~TEXT
          server {
            server_name #{Subdomains.domains(subdomain).join(" ")};
            listen 443 ssl http2;
            include /etc/letsencrypt/options-ssl-nginx.conf;
            ssl_certificate /etc/letsencrypt/live/#{Constants.domain}/fullchain.pem;
            ssl_certificate_key /etc/letsencrypt/live/#{Constants.domain}/privkey.pem;
            ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
            ssl_stapling on;
            ssl_stapling_verify on;

            #{subdomain[:backend].present? ? proxy_location("/") : frontend_locations(subdomain)}
          }
        TEXT
      end.join("\n")
    end

    def frontend_locations(subdomain)
      <<~TEXT
        root #{Subdomains.dist(subdomain)};
        index index.html;

        location / {
          try_files $uri /index.html;
        }

        location /assets/ {
          expires max;
          add_header Cache-Control "public, max-age=31536000, immutable";
        }

        #{proxy_location("/api/")}
      TEXT
    end

    def proxy_location(path)
      <<~TEXT
        location #{path} {
          proxy_pass http://127.0.0.1:3000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
      TEXT
    end
  end
end
