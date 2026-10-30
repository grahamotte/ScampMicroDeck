require "csv"
require "time"
require_relative "lib/require"

STALE_AFTER = 120
LOCKED_AFTER = 10 * 60
RUNNING_AFTER = 2 * 60 * 60
RECENT = "15 min ago"

def row(label, value)
  puts "  #{label.ljust(20)} #{value}"
end

def state_color(value)
  value == "active" ? value.green : value.red
end

def service_status(name)
  text = Cmd.ssh(
    "systemctl show --no-page --property=LoadState,ActiveState,SubState,ExecMainPID,NRestarts,MemoryCurrent #{name}.service",
    quiet: true,
  )
  text.lines.to_h { |line| line.strip.split("=", 2) }
end

def query(sql)
  sql = sql.gsub(/\s+/, " ").strip
  command = [
    "PGOPTIONS='-c default_transaction_read_only=on'",
    "psql",
    "-X",
    "-v ON_ERROR_STOP=1",
    "-P pager=off",
    "--csv",
    "-U #{Constants.deploy_user}",
    "-d #{Constants.db_name}",
    "-c ?",
  ].join(" ")

  CSV.parse(Cmd.ssh(command, sql, quiet: true), headers: true).map(&:to_h)
end

def age(value)
  return "n/a" if value.blank?

  "#{seconds_since(value).round}s ago"
end

def seconds_since(value)
  Time.now.utc - Time.parse("#{value} UTC")
end

def health(ok, text)
  ok ? text.green : text.red
end

def journal(service)
  count = Cmd
    .ssh("journalctl -u #{service} -p warning..alert --since '#{RECENT}' --no-pager --output cat | wc -l", quiet: true)
    .strip
    .to_i
  lines = Cmd
    .ssh("journalctl -u #{service} -p warning..alert --since '#{RECENT}' --no-pager --output short-iso -n 3", quiet: true)
    .lines
    .map(&:strip)
    .reject(&:blank?)

  [ count, lines ]
end

puts ""
puts "////// Deployment Status //////".magenta
puts ""

puts "#{"Domain:".ljust(20)} #{Constants.domain}".cyan
puts "#{"Instance Running:".ljust(20)} #{Instance.running? ? "Yes".green : "No".red}"

if Instance.running?
  puts "#{"IP Address:".ljust(20)} #{Instance.ip}".cyan
  puts "#{"Region:".ljust(20)} #{Constants.instance_region}".cyan
  puts "#{"Size:".ljust(20)} #{Constants.instance_size}".cyan
  puts ""

  puts "Services".magenta
  %w[api job nginx postgresql].each do |service|
    status = service_status(service)
    memory = status["MemoryCurrent"].to_i / 1024 / 1024
    detail = [
      state_color(status["ActiveState"]),
      status["SubState"],
      "pid #{status["ExecMainPID"]}",
      "restarts #{status["NRestarts"]}",
      "#{memory} MiB",
    ].join(" / ")
    row("#{service}:", detail)
  end

  puts ""
  puts "System Info".magenta
  memory = Cmd.ssh("free -h | grep Mem", quiet: true).strip.split
  disk = Cmd.ssh("df -h / | tail -1", quiet: true).strip.split
  row("Uptime:", Cmd.ssh("uptime -p", quiet: true).strip)
  row("Memory:", "#{memory[2]} used / #{memory[1]} total")
  row("Disk:", "#{disk[2]} used / #{disk[1]} total (#{disk[4]} usage)")

  hot_spots = Cmd
    .ssh("du -sh #{Constants.remote_root} /home/#{Constants.deploy_user}/tmp 2>/dev/null || true", quiet: true)
    .lines
    .map { |line| line.strip.split(/\s+/, 2).reverse.join(" ") }
    .join(" / ")
  row("Hot spots:", hot_spots)

  puts ""
  puts "Jobs".magenta

  heartbeat = query(<<~SQL).first
    SELECT
      count(*) AS processes,
      count(*) FILTER (WHERE updated_at > now() - interval '120 seconds') AS current_processes,
      max(updated_at) AS newest_heartbeat
    FROM good_job_processes
  SQL
  heartbeat_at = heartbeat["newest_heartbeat"]
  heartbeat_seconds = heartbeat_at.present? ? Time.now.utc - Time.parse("#{heartbeat_at} UTC") : Float::INFINITY
  row(
    "GoodJob heartbeat:",
    health(
      heartbeat_seconds <= STALE_AFTER,
      "#{age(heartbeat_at)} / #{heartbeat["current_processes"]} current of #{heartbeat["processes"]} process row(s)",
    ),
  )

  queue = query(<<~SQL).first
    SELECT
      count(*) AS unfinished,
      count(*) FILTER (WHERE locked_by_id IS NOT NULL) AS locked,
      min(scheduled_at) AS oldest_scheduled_at,
      min(performed_at) FILTER (WHERE locked_by_id IS NOT NULL) AS oldest_locked_performed_at
    FROM good_jobs
    WHERE finished_at IS NULL
  SQL
  locked_seconds = queue["oldest_locked_performed_at"].present? ? seconds_since(queue["oldest_locked_performed_at"]) : 0
  row(
    "GoodJob queue:",
    health(
      queue["locked"].to_i.zero? || locked_seconds <= LOCKED_AFTER,
      "#{queue["unfinished"]} unfinished / #{queue["locked"]} locked / oldest #{age(queue["oldest_scheduled_at"])}",
    ),
  )

  locked = query(<<~SQL)
    SELECT job_class, count(*) AS count, min(performed_at) AS oldest_performed_at
    FROM good_jobs
    WHERE finished_at IS NULL AND locked_by_id IS NOT NULL
    GROUP BY job_class
    ORDER BY min(performed_at) ASC
    LIMIT 5
  SQL
  locked.each do |entry|
    row("", "#{entry["job_class"]}: #{entry["count"]} locked / performing #{age(entry["oldest_performed_at"])}")
  end

  if query("SELECT to_regclass('public.jobs') AS jobs").first["jobs"].present?
    running = query(<<~SQL).first
      SELECT count(*) AS running, min(started_at) AS oldest_started_at
      FROM jobs
      WHERE status = 'running'
    SQL
    running_seconds = running["oldest_started_at"].present? ? seconds_since(running["oldest_started_at"]) : 0
    row(
      "App running jobs:",
      health(
        running_seconds <= RUNNING_AFTER,
        "#{running["running"]} running / oldest #{age(running["oldest_started_at"])}",
      ),
    )
  end

  blocked = query(<<~SQL)
    SELECT job_class, count(*) AS count, min(scheduled_at) AS oldest_scheduled_at
    FROM good_jobs
    WHERE finished_at IS NULL
    GROUP BY job_class
    ORDER BY min(scheduled_at) ASC
    LIMIT 5
  SQL
  blocked.each do |entry|
    row("", "#{entry["job_class"]}: #{entry["count"]} unfinished / oldest #{age(entry["oldest_scheduled_at"])}")
  end

  failures = query(<<~SQL).first
    SELECT count(*) AS failures
    FROM good_jobs
    WHERE finished_at > now() - interval '24 hours' AND error IS NOT NULL
  SQL
  row("GoodJob failures:", health(failures["failures"].to_i.zero?, "#{failures["failures"]} in last 24h"))

  puts ""
  puts "Database".magenta
  size = query("SELECT pg_size_pretty(pg_database_size(current_database())) AS size").first
  row("Postgres:", health(size["size"].present?, "reachable / #{size["size"]}"))

  puts ""
  puts "HTTP".magenta
  http = Cmd
    .ssh("curl --silent --show-error --output /dev/null --write-out '%{http_code} %{time_total}' #{Subdomains.url("api")}/noop/ping", quiet: true)
    .strip
    .split
  row("Ping:", health(http.first == "200", "#{http.first} / #{(http[1].to_f * 1000).round}ms"))

  puts ""
  puts "Logs".magenta
  %w[api job].each do |service|
    count, lines = journal(service)
    row("#{service} warnings:", health(count.zero?, "#{count} since #{RECENT}"))
    lines.each { |line| row("", line) } if count.positive?
  end

  puts ""
  puts "Application".magenta
  row("Branch:", Cmd.ssh("cd #{Constants.remote_root} && git rev-parse --abbrev-ref HEAD", quiet: true).strip)
  row("Commit:", Cmd.ssh("cd #{Constants.remote_root} && git rev-parse --short HEAD", quiet: true).strip)
  row("Last Deploy:", Cmd.ssh("cd #{Constants.remote_root} && git log -1 --format=%cd --date=relative", quiet: true).strip)
  dirty = Cmd
    .ssh("cd #{Constants.remote_root} && git status --porcelain", quiet: true)
    .lines
    .reject { |line| line.include?("frontend/node_modules/") }
  row("Remote changes:", health(dirty.blank?, dirty.blank? ? "clean" : "#{dirty.length} dirty file(s)"))
else
  puts ""
  puts "No active deployment found.".red
end

puts ""
