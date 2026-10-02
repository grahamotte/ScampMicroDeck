# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

class Keychain
  RENAMED = "login_renamed_*.keychain-db"

  attr_reader :home, :state_root

  def initialize(home: Dir.home, state_root: nil, runner: nil)
    @home = home
    @state_root = state_root || File.join(home, ".config", "codemoto", "keychain")
    @runner = runner
  end

  def login
    File.join(home, "Library", "Keychains", "login.keychain-db")
  end

  def snapshot
    {
      search: paths(security("list-keychains", "-d", "user")),
      default: paths(security("default-keychain", "-d", "user")).first,
    }
  end

  def protect
    saved = snapshot
    file = save(saved)
    yield saved
  ensure
    restore(saved) if saved
    FileUtils.rm_f(file) if file
  end

  def restore(saved)
    current = snapshot
    search = saved.fetch(:search, []).select { |path| usable?(path) }
    search.unshift(login) unless search.include?(login)
    default = usable?(saved[:default]) ? saved[:default] : login
    steps = []
    steps << [ "list-keychains", "-d", "user", "-s", *search ] unless current[:search] == search
    steps << [ "default-keychain", "-d", "user", "-s", default ] unless current[:default] == default
    errors = steps.filter_map do |arguments|
      security(*arguments)
      nil
    rescue StandardError => error
      error
    end
    raise errors.first if errors.any?
  end

  def release(directory = nil)
    root = File.join(File.expand_path(directory), "") if directory
    current = snapshot
    released = [ *current[:search], current[:default] ].compact.uniq.select do |path|
      !File.exist?(path) || (root && path.start_with?(root))
    end
    return [] if released.empty?

    restore(
      search: current[:search] - released,
      default: released.include?(current[:default]) ? login : current[:default],
    )
    released
  end

  def recover
    states.reject { |state| alive?(state[:pid]) }.map do |state|
      restore(state[:snapshot])
      FileUtils.rm_f(state[:file])
      state[:file]
    end
  end

  def busy?
    states.any? { |state| alive?(state[:pid]) }
  end

  def problems
    return [] if busy?

    current = snapshot
    found = []
    found << "#{login} is missing" unless File.exist?(login)
    found << "default keychain is #{current[:default] || "unset"}, not #{login}" unless current[:default] == login
    found << "search list does not include #{login}" unless current[:search].include?(login)
    renamed.each { |path| found << "#{path} is larger than #{login} and may hold the original login keychain" }
    found
  end

  def repair
    recover
    replaced = restore_renamed
    restore(search: snapshot[:search], default: login)
    replaced
  end

  private

  def restore_renamed
    original = renamed.max_by { |path| File.size(path) }
    return if original.nil?

    backup = File.join(File.dirname(login), "login_backup_#{Time.now.strftime("%Y%m%d%H%M%S")}.keychain-db")
    FileUtils.cp(login, backup) if File.exist?(login)
    FileUtils.cp(original, login)
    { original:, backup: File.exist?(backup) ? backup : nil }
  end

  def renamed
    size = File.exist?(login) ? File.size(login) : 0
    Dir.glob(File.join(File.dirname(login), RENAMED)).sort.select { |path| File.size(path) > size }
  end

  def save(saved)
    FileUtils.mkdir_p(state_root)
    file = File.join(state_root, "#{Time.now.strftime("%Y%m%d%H%M%S%N")}-#{Process.pid}.json")
    File.write(file, JSON.generate(pid: Process.pid, snapshot: saved))
    file
  end

  def states
    Dir.glob(File.join(state_root, "*.json")).sort.reverse.filter_map do |file|
      state = JSON.parse(File.read(file), symbolize_names: true)
      state.merge(file:)
    rescue JSON::ParserError
      FileUtils.rm_f(file)
      nil
    end
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::EPERM
    true
  rescue Errno::ESRCH, RangeError, TypeError
    false
  end

  def usable?(path)
    !path.nil? && File.exist?(path)
  end

  def paths(output)
    output.scan(/"([^"]+)"/).flatten
  end

  def security(*arguments)
    return @runner.call(*arguments) if @runner

    stdout, stderr, status = Open3.capture3("security", *arguments)
    raise "security #{arguments.join(" ")} failed: #{stderr.strip}" unless status.success?

    stdout
  end
end
