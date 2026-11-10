require_relative "lib/require"

output = $stdout
$stdout = $stderr

command = ARGV.join(" ").strip

if command.blank?
  warn "Usage: mise deploy:cmd \"journalctl -u api -n 100 --no-pager\""
  exit 1
end

Cmd.ssh(command, out: output, err: $stderr)
