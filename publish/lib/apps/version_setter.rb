module Apps
  class VersionSetter
    def self.call(version, root: Constants.local_root)
      raise "Invalid version #{version}" unless version.match?(/\A\d+\.\d+\.\d+\z/)

      config_path = File.join(root, "config.json")
      config = JSON.parse(File.read(config_path))
      apps = config.fetch("apps")
      targets = apps.fetch("targets")
      unsupported = targets.find { |platform, configured| configured.present? && platform != "apple" }
      raise "Unsupported deploy target #{unsupported.first}" if unsupported.present?

      targets.fetch("apple", {}).each_value.map { |target| target.fetch("project") }.uniq.each do |project|
        set_xcode_version(File.expand_path(project, root), version)
      end
      apps["version"] = version
      apps["build"] = version
      File.write(config_path, "#{JSON.pretty_generate(config)}\n")
    end

    def self.set_xcode_version(project, version)
      path = File.join(project, "project.pbxproj")
      contents = File.read(path).gsub(/(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = [^;]+;/, "\\1 = #{version};")
      File.write(path, contents)
    end
  end
end
