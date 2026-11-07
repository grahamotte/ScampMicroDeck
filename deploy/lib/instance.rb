class Instance
  class << self
    def clear
      instance_variables.each do |var_name|
        instance_variable_set(var_name, nil)
      end
    end

    def image_id
      @image_id ||= req(
        :get,
        "images",
        params: { type: "distribution", per_page: 200 },
        quiet: true
      )
        .dig(:images)
        .select do |image|
          match = image[:slug].match(/\Aubuntu-(\d{2})-04-x64\z/)
          match.present? && match[1].to_i.even?
        end
        .max_by { |image| image[:slug] }
        .dig(:id)
    end

    def ssh_key_id
      @ssh_key_id ||= begin
        keys = req(
          :get,
          "account/keys",
          quiet: true
        )
        found = keys.dig(:ssh_keys).find { |x| x[:fingerprint] == Constants.ssh_key_fingerprint }

        if found.present?
          found.fetch(:id)
        else
          res = req(
            :post,
            "account/keys",
            payload: { name: Constants.domain, public_key: Constants.ssh_key_pub }
          )
          res.dig(:ssh_key).fetch(:id)
        end
      end
    end

    def show
      @show ||= req(
        :get,
        "droplets",
        params: { per_page: 200 },
        quiet: true
      )
        .dig(:droplets)
        .find { |x| x[:name] == Constants.domain } || {}
    end

    def instance_id
      @instance_id ||= show[:id]
    end

    def running?
      @running ||= show[:status] == "active" && ip.present?
    end

    def ip
      @ip ||= show
        .dig(:networks, :v4)
        &.find { |x| x[:type] == "public" }
        &.dig(:ip_address)
    end

    def create
      req(
        :post,
        "droplets",
        payload: {
          name: Constants.domain,
          region: Constants.instance_region,
          image: image_id,
          size: Constants.instance_size,
          ssh_keys: [ ssh_key_id ],
        },
        quiet: true
      )
    end

    def destroy
      raise "nothing to destroy :(" if instance_id.blank?

      req(
        :delete,
        "droplets/#{instance_id}"
      )
    end

    def service_running?(service)
      Cmd.ssh("systemctl show --no-page --property=LoadState,ActiveState,FreezerState #{service}.service")
        .split("\n")
        .map { |x| x.split("=").last.strip }
        .join(" ") == "loaded active running"
    end

    def stop_service(service)
      Cmd.ssh("sudo systemctl stop #{service}.service")
    rescue StandardError => e
      puts e.message
    end

    def start_service(service)
      Cmd.ssh("sudo systemctl daemon-reload")
      Cmd.ssh("sudo systemctl start #{service}.service")
      Cmd.ssh("sudo systemctl enable #{service}.service")
      sleep(3)
      raise "Failed to start #{service}" unless service_running?(service)
    end

    def write_service(service, definition)
      path = "/etc/systemd/system/#{service}.service"
      if Cache.unchanged?(path, definition)
        puts "INSTANCE skip write to #{service} because it hasn't changed"
        return
      end

      Cmd.ssh_write(path, definition, sudo: true)
      Cmd.ssh("sudo systemctl daemon-reload")
      Cmd.ssh("sudo systemctl enable #{service}.service")
      Cache.set(path, definition)
    end

    def app_environment
      {
        "MISE_DATA_DIR" => Constants.remote_mise_data_dir,
        "MISE_TRUSTED_CONFIG_PATHS" => Constants.remote_root,
      }
    end

    def app_command(command)
      [
        "sudo -u #{Constants.app_user} -H env",
        *app_environment.map { |key, value| "#{key}=#{Shellwords.escape(value)}" },
        "bash -c #{Shellwords.escape(command)}",
      ].join(" ")
    end

    def restart_service(service)
      stop_service(service)
      start_service(service)
    end

    def installed?(package)
      Cmd.ssh("which #{package}").present?
    rescue StandardError => e
      puts e.message
      false
    end

    def not_installed?(package)
      !installed?(package)
    end

    def install_package(package, bin: package)
      return if installed?(bin)

      Cmd.ssh("sudo apt-get install -y #{package}")
    end

    private

    def req(method, path, params: {}, payload: {}, quiet: false)
      Req.call(
        method:,
        url: "https://api.digitalocean.com/v2/#{path}",
        params:,
        payload:,
        headers: { "Authorization" => "Bearer #{Constants.digital_ocean_token}" },
        quiet:
      )
    end
  end
end
