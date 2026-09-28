require_relative "lib/require"

begin
  raise "Usage: #{__FILE__} <new_app_name>" unless ARGV.length == 1

  Spawner.new(ARGV.fetch(0)).call
rescue StandardError => error
  warn "Error: #{error.message}"
  exit 1
end
