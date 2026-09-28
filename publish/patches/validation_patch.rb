module Apps
  class ValidationPatch < BasePatch
    class << self
      def apply
        Cmd.local("xcodebuild -version")
        validate_checkout
        validate_environment
        validate_release
        validate_targets
        Apps.private_key
      end

      private

      def validate_checkout
        Cmd.local("git fetch origin master")
        raise "Uncommitted changes; publish from a clean checkout of origin/master" if Cmd.local("git status --porcelain").present?
        return if Cmd.local("git rev-parse HEAD").strip == Cmd.local("git rev-parse origin/master").strip

        raise "HEAD is not origin/master; publish from a clean checkout of origin/master"
      end

      def validate_environment
        required = %w[
          APPLE_ISSUER_ID
          APPLE_DEVELOPMENT_CERTIFICATE_BASE64
          APPLE_DEVELOPMENT_CERTIFICATE_PASSWORD
          APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
          APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
          APPLE_KEY_ID
          APPLE_KEY_SECRET_BASE64
          APPLE_TEAM_ID
          GITHUB_TOKEN
        ]
        unless Apps.skip_app_stores?
          required.concat(%w[
            APPLE_DISTRIBUTION_CERTIFICATE_BASE64
            APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD
            APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64
            APPLE_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD
          ])
        end
        required.each do |name|
          raise "Missing #{name}" if ENV[name].blank?
        end
        raise "Missing githubRepo in config.json" if Constants.github_repo.blank?
        Apps.revision_repositories
      end

      def validate_release
        unless [ true, false ].include?(Apps.config.fetch(:skip_app_stores, false))
          raise "skip_app_stores must be true or false in app configuration"
        end

        required = %i[
          build
          name
          whatsNew
        ]
        unless Apps.skip_app_stores?
          required.concat(%i[
            contactEmail
            contactFirstName
            contactLastName
            contactPhone
            copyright
            description
            keywords
            marketingUrl
            notes
            promotionalText
            releaseType
            supportUrl
          ])
        end
        required.each do |field|
          raise "Missing #{field} in app configuration" if Apps.config[field].blank?
        end
        return if Apps.skip_app_stores?

        Apps.config.fetch(:reviewAttachments, []).each do |attachment|
          raise "Missing review attachment path in app configuration" if attachment[:path].blank?
          raise "Missing #{attachment.fetch(:path)}" unless File.file?(Apps.review_attachment_path(attachment))
        end
        raise "Missing demoAccountRequired in app configuration" unless Apps.config.key?(:demoAccountRequired)
        return unless Apps.config.fetch(:demoAccountRequired)

        %i[demoAccountName demoAccountPassword].each do |field|
          raise "Missing #{field} in app configuration" if Apps.config[field].blank?
        end
      end

      def validate_targets
        raise "No Apple targets configured" if Apps.targets.blank?
        raise "Missing macOS target for repository release" if Apps.skip_app_stores? && Apps.targets.none? { |target| target.fetch(:platform) == "MAC_OS" }
        raise "Missing #{Apps.export_options_path}" if !Apps.skip_app_stores? && !File.file?(Apps.export_options_path)

        Apps.targets.each do |target|
          required = %i[archiveDestination bundleIdentifier platform project scheme]
          required << :screenshots unless Apps.skip_app_stores?
          required.each do |field|
            raise "Missing #{field} for #{target.fetch(:name)}" if target[field].blank?
          end
          raise "Missing #{target.fetch(:project)}" unless File.directory?(Apps.project_path(target))
          next if Apps.skip_app_stores?

          target.fetch(:screenshots).each do |screenshot|
            %i[displayType path].each do |field|
              raise "Missing screenshot #{field} for #{target.fetch(:name)}" if screenshot[field].blank?
            end
            raise "Missing #{screenshot.fetch(:path)}" unless File.file?(Apps.screenshot_path(screenshot))
          end
        end
      end
    end
  end
end
