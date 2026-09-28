module Apps
  class BuildPatch < BasePatch
    class << self
      def needed?
        Apps.targets.any? do |target|
          !File.directory?(Apps.archive_path(target)) || Cache.get(cache_key(target)).blank?
        end
      end

      def apply
        Apps.targets.each do |target|
          next if File.directory?(Apps.archive_path(target)) && Cache.get(cache_key(target)).present?

          puts "Building #{target.fetch(:name)}..."
          FileUtils.rm_rf(Apps.archive_path(target))
          FileUtils.mkdir_p(File.dirname(Apps.archive_path(target)))
          Apps.with_signing_certificate("Apple Development", "APPLE_DEVELOPMENT") do |keychain|
            Cmd.local(Shellwords.join([
              "xcodebuild",
              "archive",
              "-project",
              Apps.project_path(target),
              "-scheme",
              target.fetch(:scheme),
              "-configuration",
              "Release",
              "-destination",
              target.fetch(:archiveDestination),
              "-archivePath",
              Apps.archive_path(target),
              "-allowProvisioningUpdates",
              "MARKETING_VERSION=#{Apps.version}",
              "CURRENT_PROJECT_VERSION=#{Apps.build}",
              "#{target.fetch(:bundleIdentifierBuildSetting, "PRODUCT_BUNDLE_IDENTIFIER")}=#{target.fetch(:bundleIdentifier)}",
              "DEVELOPMENT_TEAM=#{ENV.fetch("APPLE_TEAM_ID")}",
              "OTHER_CODE_SIGN_FLAGS=--keychain #{keychain}",
              *Apps.authentication_arguments,
              *(target.fetch(:platform) == "MAC_OS" ? [ "ENABLE_HARDENED_RUNTIME=YES" ] : []),
            ]))
          end
          Cache.set(cache_key(target), "built")
        end
      end

      private

      def cache_key(target)
        "apps/#{Apps.version}/#{target.fetch(:name)}/archive/v5"
      end
    end
  end
end
