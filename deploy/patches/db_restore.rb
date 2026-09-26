class DbRestorePatch < BasePatch
  class << self
    def always
      Cmd.ssh("sudo apt-get install -y awscli") unless Instance.installed?("aws")

      key = backup_keys.last
      path = File.join(Constants.remote_home_dir, key)

      aws_cmd("s3 cp s3://#{Constants.backup_bucket}/#{key} #{path}")

      Instance.stop_service("job")
      Instance.stop_service("api")

      begin
        Cmd.ssh("psql -v ON_ERROR_STOP=1 #{Constants.db_name} < #{path}")
        Instance.start_service(:postgresql)

        Cmd.ssh("rm -f #{path}")
      ensure
        Instance.start_service("job")
        Instance.start_service("api")
      end
    end

    private

    def aws_cmd(cmd)
      Cmd.ssh(
        [
          "export AWS_ACCESS_KEY_ID=#{Constants.backup_access_key_id};",
          "export AWS_SECRET_ACCESS_KEY=#{Constants.backup_secret_access_key};",
          "export AWS_REQUEST_CHECKSUM_CALCULATION=WHEN_REQUIRED;",
          "export AWS_RESPONSE_CHECKSUM_VALIDATION=WHEN_REQUIRED;",
          "aws --endpoint-url #{Constants.backup_endpoint}",
          cmd,
        ].join(" ")
      )
    end

    def backup_keys
      result = aws_cmd("s3 ls s3://#{Constants.backup_bucket}/")

      result
        .split("\n")
        .map(&:split)
        .map(&:last)
        .select { |x| x.present? && x.start_with?(Constants.db_name) }
        .sort
    end
  end
end

# module Patches
#   class DbRestore < Base
#     class << self
#       def needed?
#         return false unless backups_setup?
#         return false unless Instance.exists?

#         true
#       end

#       def apply
#         Instance.stop_service(:postgresql)
#         sleep(5)

#         install_aws_cli

#         key = backup_keys.last
#         path = "#{home}/#{key}"

#         remote_cmd("#{aws_cli_s3} cp s3://#{Secrets.all.dig(:backup_bucket, :bucket)}/#{key} #{path}")
#         remote_cmd("psql #{db_name} < #{path}")

#         sleep(5)
#         Instance.start_service(:postgresql)
#       ensure
#         remote_cmd("rm -f #{path}")
#       end
#     end
#   end
# end
