require_relative "lib/require"

begin
  exit KeychainRepair.new.call ? 0 : 1
rescue StandardError => error
  warn "Error: #{error.message}"
  exit 1
end
