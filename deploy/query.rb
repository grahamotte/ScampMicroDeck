require_relative "lib/require"
require "csv"
require "json"

json = $stdout
$stdout = $stderr

query = ARGV.join(" ").strip

if query.blank?
  warn "Usage: mise query:production \"select count(*) from table_name\""
  exit 1
end

unless /\A\s*(select|with|show|explain|table|values)\b/i.match?(query)
  warn "Only read-only query forms are allowed: SELECT, WITH, SHOW, EXPLAIN, TABLE, VALUES"
  exit 1
end

begin
  output = Cmd.ssh(
    [
      "PGCLIENTENCODING=UTF8",
      "PGOPTIONS='-c default_transaction_read_only=on -c client_min_messages=error'",
      "psql",
      "-X",
      "-v ON_ERROR_STOP=1",
      "-P pager=off",
      "--csv",
      "-U ?",
      "-d ?",
      "-c ?",
    ].join(" "),
    Constants.deploy_user,
    Constants.db_name,
    query,
    quiet: true,
  )
rescue Cmd::SshError => e
  warn e.output.present? ? e.output : e.message
  exit 1
end

csv = CSV.parse(output, headers: true)
json.puts JSON.pretty_generate(csv.map(&:to_h))
