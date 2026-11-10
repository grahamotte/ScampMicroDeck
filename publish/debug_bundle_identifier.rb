require_relative "lib/require"

target = Apps.targets.find { |candidate| candidate.fetch(:platform) == "MAC_OS" }
raise "config.json has no macOS app target" if target.blank?

puts Apps.debug_bundle_identifier(target)
