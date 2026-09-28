require_relative "lib/require"

client = Apps::AppStoreConnect.new
versions = Apps.targets.filter_map { |target| client.latest_approved_version(target) }

puts versions.max_by { |version| Gem::Version.new(version) } || "none"
