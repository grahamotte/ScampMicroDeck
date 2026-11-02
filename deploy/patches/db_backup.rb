class DbBackupPatch < BasePatch
  class << self
    def always
      Cmd.ssh("sudo apt-get install -y awscli") unless Instance.installed?('aws')

      key = "#{Constants.db_name}_#{Time.now.to_i}.sql"
      path = File.join(Constants.remote_home_dir, key)

      Cmd.ssh("/usr/bin/pg_dump -U #{Constants.deploy_user} --clean #{Constants.db_name} > #{path}")

      Cmd.ssh(
        [
          "read -r AWS_ACCESS_KEY_ID; read -r AWS_SECRET_ACCESS_KEY;",
          "export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY;",
          "export AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED;",
          "export AWS_RESPONSE_CHECKSUM_VALIDATION=WHEN_REQUIRED;",
          "aws --endpoint-url #{Constants.backup_endpoint} s3 cp #{path} s3://#{Constants.backup_bucket}/#{key}",
        ].join(" "),
        stdin: "#{Constants.backup_access_key_id}\n#{Constants.backup_secret_access_key}\n",
      )

      Cmd.ssh("rm -f #{path}")

      # remote_cmd("#{aws_cli_s3} cp #{path} s3://#{Secrets.all.dig(:backup_bucket, :bucket)}/#{key}")

      # backup_keys
      #   .select { |x| x.split('.').first.split('_').last.to_i < (Time.now.to_i - (86_400 * 30)) }
      #   .each { |x| remote_cmd("#{aws_cli_s3} rm s3://#{Secrets.all.dig(:backup_bucket, :bucket)}/#{x}") }
      # ensure
      #   remote_cmd("rm -f #{path}")
    end
  end
end
