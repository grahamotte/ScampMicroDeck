module Sources
  class Backend
    class << self
      def droplet? = true

      def locations(_subdomain)
        proxy_location("/")
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
end
