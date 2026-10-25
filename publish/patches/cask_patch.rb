module Apps
  class CaskPatch < BasePatch
    class << self
      def needed?
        Apps.homebrew.present? && target.present?
      end

      def apply
        raise "Missing revision for #{target.fetch(:name)}" unless File.file?(Apps.revision_path(target))

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, cask)
        command = "cd #{Shellwords.escape(Apps.main_root)} && " + Shellwords.join([ "mr", "cask", "--file", path ])
        Bundler.with_unbundled_env { Cmd.local(command) }
      end

      private

      def cask
        homebrew = Apps.homebrew
        lines = [
          "cask #{token.to_json} do",
          "  version #{Apps.version.to_json}",
          "  sha256 #{Digest::SHA256.file(Apps.revision_path(target)).hexdigest.to_json}",
          "",
          "  url \"#{url}\"",
          "  name #{Apps.config.fetch(:name).to_json}",
          "  desc #{homebrew.fetch(:desc).to_json}",
          "  homepage #{homepage.to_json}",
          "",
          "  livecheck do",
          "    url :url",
          "    strategy :github_latest",
          "  end",
          "",
          "  depends_on macos: :#{homebrew.fetch(:macos)}",
          "",
          "  app #{"#{Apps.config.fetch(:name)}.app".to_json}",
        ]
        zap = homebrew.fetch(:zap, []).sort
        if zap.one?
          lines << ""
          lines << "  zap trash: #{zap.first.to_json}"
        elsif zap.present?
          lines << ""
          lines << "  zap trash: ["
          zap.each { |item| lines << "    #{item.to_json}," }
          lines << "  ]"
        end
        lines << "end"
        "#{lines.join("\n")}\n"
      end

      def target = Apps.targets.find { |item| item.fetch(:platform) == "MAC_OS" }

      def token = Apps.config.fetch(:name).downcase.gsub(/[^a-z0-9]+/, "-").sub(/\A-/, "").sub(/-\z/, "")

      def homepage
        url = Apps.config.fetch(:marketingUrl)
        URI.parse(url).path.blank? ? "#{url}/" : url
      end

      def path = File.join(Apps.tmp_root, Apps.version, "cask", "#{token}.rb")

      def url
        asset = File.basename(Apps.revision_path(target)).sub(Apps.version, "\#{version}")
        "https://github.com/#{Apps.github_repository}/releases/download/v\#{version}/#{asset}"
      end
    end
  end
end
