require_relative "lib/require"

code = ARGV.join(" ").strip

if code.blank?
  warn "Usage: mise runner:production \"User.first\""
  exit 1
end

Cmd.ssh(
  Instance.app_command(
    "cd #{Shellwords.escape(File.join(Constants.remote_root, "backend"))} && set -a && source ../.env && RAILS_ENV=production mise exec -- bundle exec rails runner #{Shellwords.escape(code)}",
  ),
)
