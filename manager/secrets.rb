require_relative "lib/require"

begin
  Secrets.new.call
rescue StandardError => error
  warn "Error: #{error.message}"
  exit 1
end
