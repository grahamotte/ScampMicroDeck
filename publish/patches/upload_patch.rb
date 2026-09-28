module Apps
  class UploadPatch < BasePatch
    class << self
      def needed?
        !Apps.skip_app_stores? && Apps.targets.any? { |target| Cache.get(cache_key(target)).blank? }
      end

      def apply
        Apps.targets.each do |target|
          next if Cache.get(cache_key(target)).present?

          raise "Missing archive for #{target.fetch(:name)}" unless File.directory?(Apps.archive_path(target))

          puts "Uploading #{target.fetch(:name)}..."
          FileUtils.rm_rf(Apps.export_path(target))
          certificates = [ [ "Apple Distribution", "APPLE_DISTRIBUTION", "codesigning" ] ]
          certificates << [ "Mac Developer Installer", "APPLE_MAC_INSTALLER_DISTRIBUTION", nil ] if target.fetch(:platform) == "MAC_OS"
          Apps.with_signing_certificates(certificates) do |keychain|
            Cmd.local(Shellwords.join([
              "xcodebuild",
              "-exportArchive",
              "-archivePath",
              Apps.archive_path(target),
              "-exportPath",
              Apps.export_path(target),
              "-exportOptionsPlist",
              Apps.export_options_path,
              "-allowProvisioningUpdates",
              "OTHER_CODE_SIGN_FLAGS=--keychain #{keychain}",
              *Apps.authentication_arguments,
            ]))
          end
          Cache.set(cache_key(target), "uploaded")
        end
      end

      private

      def cache_key(target)
        "apps/#{Apps.version}/#{target.fetch(:name)}/uploaded"
      end
    end
  end
end
