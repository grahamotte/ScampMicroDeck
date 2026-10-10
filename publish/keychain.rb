require_relative "lib/require"

begin
  exit Apps::KeychainTask.call(repair: ARGV.include?("--repair")) ? 0 : 1
rescue StandardError => error
  warn "Error: #{error.message}"
  exit 1
end
