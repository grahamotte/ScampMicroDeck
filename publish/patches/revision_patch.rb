module Apps
  class RevisionPatch < BasePatch
    class << self
      def needed?
        targets.any? { |target| Cache.get(cache_key(target)).blank? }
      end

      def apply
        targets.each do |target|
          raise "Missing archive for #{target.fetch(:name)}" unless File.directory?(Apps.archive_path(target))

          package(target)
          release(target)
        end
      end

      private

      def targets = Apps.targets.select { |target| target.fetch(:platform) == "MAC_OS" }

      def package(target)
        return if File.file?(Apps.revision_path(target))

        FileUtils.rm_rf(Apps.revision_export_path(target))
        FileUtils.mkdir_p(Apps.revision_export_path(target))
        FileUtils.mkdir_p(File.dirname(Apps.revision_path(target)))
        export(target)
        product = revision_product(target)
        Cmd.local(Shellwords.join([ "codesign", "--verify", "--deep", "--strict", product ]))
        Cmd.local(Shellwords.join([ "ditto", "-c", "-k", "--keepParent", product, Apps.revision_path(target) ]))
        notarize(product, target)
      end

      def notarize(product, target)
        result = Cmd.local(Shellwords.join([
          "xcrun",
          "notarytool",
          "submit",
          Apps.revision_path(target),
          "--key",
          Apps.private_key_path,
          "--key-id",
          ENV.fetch("APPLE_KEY_ID"),
          "--issuer",
          ENV.fetch("APPLE_ISSUER_ID"),
          "--wait",
        ]))
        raise "Notarization failed for #{target.fetch(:name)}" unless result.include?("status: Accepted")
        Cmd.local(Shellwords.join([ "xcrun", "stapler", "staple", product ]))
        Cmd.local(Shellwords.join([ "spctl", "--assess", "--type", "execute", product ]))
        FileUtils.rm_f(Apps.revision_path(target))
        Cmd.local(Shellwords.join([ "ditto", "-c", "-k", "--keepParent", product, Apps.revision_path(target) ]))
      end

      def export(target)
        Apps.with_signing_certificate("Developer ID Application", "APPLE_DEVELOPER_ID") do |keychain|
          export_archive(target, keychain)
          Cmd.local(Shellwords.join([
            "codesign",
            "--force",
            "--deep",
            "--options",
            "runtime",
            "--timestamp",
            "--preserve-metadata=entitlements,requirements",
            "--sign",
            "Developer ID Application",
            "--keychain",
            keychain,
            revision_product(target),
          ]))
        end
      end

      def export_archive(target, keychain)
        Tempfile.create([ "revision-export", ".plist" ]) do |file|
          file.write(export_options(target))
          file.close
          Cmd.local(Shellwords.join([
            "xcodebuild",
            "-exportArchive",
            "-archivePath",
            Apps.archive_path(target),
            "-exportPath",
            Apps.revision_export_path(target),
            "-exportOptionsPlist",
            file.path,
            "-allowProvisioningUpdates",
            "OTHER_CODE_SIGN_FLAGS=--keychain #{keychain}",
            *Apps.authentication_arguments,
          ]))
        end
      end

      def export_options(_target)
        <<~PLIST
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>destination</key>
            <string>export</string>
            <key>method</key>
            <string>developer-id</string>
            <key>signingCertificate</key>
            <string>Developer ID Application</string>
            <key>signingStyle</key>
            <string>automatic</string>
            <key>teamID</key>
            <string>#{ENV.fetch("APPLE_TEAM_ID")}</string>
          </dict>
          </plist>
        PLIST
      end

      def revision_product(target)
        products = Dir.glob(File.join(Apps.revision_export_path(target), "*.app"))
        raise "Missing revision for #{target.fetch(:name)}" unless products.one?

        product = products.fetch(0)
        named_product = File.join(Apps.revision_export_path(target), "#{Apps.config.fetch(:name)}.app")
        FileUtils.mv(product, named_product) unless product == named_product
        named_product
      end

      def release(target)
        return if Cache.get(cache_key(target)).present?

        Tempfile.create([ "release-notes", ".md" ]) do |file|
          file.write(Apps.config.fetch(:whatsNew))
          file.close
          command = "cd #{Shellwords.escape(Apps.main_root)} && " + Shellwords.join([
            "mr",
            "release",
            "--tag",
            tag,
            "--notes-file",
            file.path,
            "--asset",
            Apps.revision_path(target),
            "--obsolete-suffix",
            "-#{target.fetch(:name)}-#{Apps.version}.zip",
          ])
          Bundler.with_unbundled_env { Cmd.local(command) }
        end
        Cache.set(cache_key(target), "uploaded")
      end

      def tag = "v#{Apps.version}"

      def cache_key(target)
        "apps/#{Apps.version}/#{target.fetch(:name)}/revisions/v4"
      end
    end
  end
end
