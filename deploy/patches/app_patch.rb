class AppPatch < BasePatch
  class << self
    def always
      Cache.if_files_changed(File.expand_path("../frontend/pnpm-lock.yaml")) do
        Cmd.ssh("cd #{Constants.remote_root}/frontend; mise exec -- pnpm install --frozen-lockfile")
      end

      Cache.if_files_changed(File.expand_path("../backend/Gemfile.lock")) do
        Cmd.ssh("cd #{Constants.remote_root}/backend; mise exec -- bundle install")
      end

      Instance.stop_service("api")
      Instance.stop_service("job")

      Cache.if_files_changed(Dir.glob(File.expand_path("../backend/db/migrate/*"))) do
        Cmd.ssh("cd #{Constants.remote_root}/backend; set -a; source ../.env; mise exec -- bin/rails db:migrate")
      end

      Cmd.ssh("rm -rf ~/tmp")

      Instance.write_service("api", api_service)
      Instance.write_service("job", job_service)
      Cmd.ssh("sudo systemctl start api.service")
      Cmd.ssh("sudo systemctl start job.service")


      Subdomains.frontends.each do |subdomain|
        Cmd.ssh("cd #{Constants.remote_root}/frontend; set -a; source ../.env; VITE_SUBDOMAIN=#{subdomain.fetch(:name)} mise exec -- pnpm exec vite build")
      end
      # Cmd.local("cd #{Constants.local_root}; set -a; source .env.production; cd frontend; mise exec -- pnpm exec vite build")
      # Cmd.local("rsync -av -e \"ssh -i #{Constants.ssh_key_path}\" #{Constants.local_root}/frontend/dist/ #{Constants.deploy_user}@#{Instance.ip}:#{Constants.remote_root}/frontend/dist/")

      begin
        Req.call(method: :get, url: "https://#{Constants.domain}/api/noop/ping")
      rescue StandardError => e
        puts "#{e.message} - waiting for rails to start..."
        sleep 1
        retry
      end
    end

    private

    def api_service = <<~TEXT
      [Unit]
      Description=Api
      Wants=network-online-target
      After=network-online-target

      [Service]
      User=#{Constants.deploy_user}
      Type=simple
      ExecStart=/usr/bin/bash -c 'cd #{Constants.remote_root}/backend && set -a && source ../.env && mise exec -- bin/rails server --binding 127.0.0.1 --port 3000'
      Restart=always
      TimeoutStopSec=5
      MemoryMax=1200M

      [Install]
      WantedBy=default.target
    TEXT

    def job_service = <<~TEXT
      [Unit]
      Description=Job Worker
      Wants=network-online-target
      After=network-online-target

      [Service]
      User=#{Constants.deploy_user}
      Type=simple
      Environment=GOOD_JOB_ENABLE_CRON=true
      ExecStart=/usr/bin/bash -c 'cd #{Constants.remote_root}/backend && set -a && source ../.env && mise exec -- bundle exec good_job start'
      Restart=always
      TimeoutStopSec=5
      MemoryHigh=384M
      MemoryMax=4096M

      [Install]
      WantedBy=default.target
    TEXT
  end
end
