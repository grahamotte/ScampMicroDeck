require_relative "lib/require"

version = if Apps.skip_app_stores?
  Apps.latest_released_version
else
  client = Apps::AppStoreConnect.new
  Apps.targets
    .filter_map { |target| client.latest_approved_version(target) }
    .max_by { |version| Gem::Version.new(version) }
end

puts version || "none"
