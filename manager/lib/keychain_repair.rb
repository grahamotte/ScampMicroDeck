class KeychainRepair
  def initialize(keychain: Worktree.keychain, output: $stdout)
    @keychain = keychain
    @output = output
  end

  def call
    if @keychain.busy?
      @output.puts "A task is using a temporary keychain. Run this again after it finishes."
      return false
    end

    problems = @keychain.problems
    if problems.blank?
      @output.puts "The host keychain configuration is healthy."
      return true
    end

    problems.each { |problem| @output.puts "- #{problem}" }
    replaced = @keychain.repair
    if replaced.present?
      @output.puts "Restored #{@keychain.login} from #{replaced[:original]}."
      @output.puts "Saved the previous login keychain to #{replaced[:backup]}." if replaced[:backup].present?
      @output.puts "Log out and back in so macOS reloads the login keychain."
    end
    @output.puts "Reset the default keychain and search list to #{@keychain.login}."

    remaining = @keychain.problems
    remaining.each { |problem| @output.puts "Still needs attention: #{problem}" }
    remaining.blank?
  end
end
