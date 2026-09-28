module Apps
  class Simulator
    ALIASES = {
      mac: :macos,
      osx: :macos,
      phone: :iphone,
      tablet: :ipad,
      tvos: :tv,
    }.freeze

    class << self
      def call(name)
        target, device = simulator(name)
        derived_data_path = File.join(Apps.tmp_root, "simulate", target.fetch(:name).to_s)
        stop(target)
        build(target, derived_data_path)
        launch(target, device, derived_data_path)
      end

      private

      def simulator(name)
        name = ALIASES.fetch(name.to_sym, name.to_sym)
        Apps.targets.each do |target|
          device = target.fetch(:simulators, {})[name]
          return [ target, device ] if device.present?
        end
        choices = Apps.targets.flat_map { |target| target.fetch(:simulators, {}).keys }.join(", ")
        raise "Unknown simulator: #{name}. Choose #{choices}"
      end

      def stop(target)
        return unless target.fetch(:platform) == "MAC_OS"

        process = File.basename(target.fetch(:simulatorProduct), ".app")
        Cmd.local(Shellwords.join([ "pkill", "-x", process ])) rescue nil
      end

      def build(target, derived_data_path)
        FileUtils.rm_rf(product_path(target, derived_data_path))
        Cmd.local(Shellwords.join([
          "xcodebuild",
          "-project",
          Apps.project_path(target),
          "-scheme",
          target.fetch(:scheme),
          "-configuration",
          "Debug",
          "-destination",
          target.fetch(:simulatorDestination),
          "-derivedDataPath",
          derived_data_path,
          "build",
          "#{target.fetch(:bundleIdentifierBuildSetting, "PRODUCT_BUNDLE_IDENTIFIER")}=#{target.fetch(:bundleIdentifier)}",
        ]))
      end

      def launch(target, device, derived_data_path)
        app_path = product_path(target, derived_data_path)
        return Cmd.local(Shellwords.join([ "open", app_path ])) if target.fetch(:platform) == "MAC_OS"

        udid, booted = available_simulator(device)
        unless booted
          Cmd.local(Shellwords.join([ "xcrun", "simctl", "boot", udid ])) rescue nil
          Cmd.local(Shellwords.join([ "xcrun", "simctl", "bootstatus", udid, "-b" ]))
        end
        open_simulator(udid)
        bundle_identifier = target.fetch(:bundleIdentifier)
        Cmd.local(Shellwords.join([ "xcrun", "simctl", "terminate", udid, bundle_identifier ])) rescue nil
        Cmd.local(Shellwords.join([ "xcrun", "simctl", "install", udid, app_path ]))
        Cmd.local(Shellwords.join([ "xcrun", "simctl", "launch", udid, bundle_identifier ]))
      end

      def available_simulator(device)
        devices = Cmd.local("xcrun simctl list devices available")
        matching = devices.lines.filter { |line| line.include?(device) }
        line = matching.find { |line| line.include?("(Booted)") } || matching.first
        udid = line&.match(/[0-9A-F-]{36}/)&.to_s
        raise "No available #{device} simulator found" if udid.blank?

        [ udid, line.include?("(Booted)") ]
      end

      def open_simulator(udid)
        Cmd.local("open -b com.apple.dt.Devices")
      rescue StandardError
        Cmd.local(Shellwords.join([ "open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", udid ]))
      end

      def product_path(target, derived_data_path)
        File.join(derived_data_path, "Build", "Products", target.fetch(:simulatorProduct))
      end
    end
  end
end
