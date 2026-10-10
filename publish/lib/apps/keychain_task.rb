module Apps
  class KeychainTask
    def self.call(repair: false, keychain: Apps.host_keychain, output: $stdout)
      new(keychain:, output:).call(repair:)
    end

    def initialize(keychain:, output:)
      @keychain = keychain
      @output = output
    end

    def call(repair:)
      if @keychain.busy?
        @output.puts "A signing run is using a temporary keychain. Run this again after it finishes."
        return !repair
      end

      @keychain.recover.each { |file| @output.puts "restored keychains from #{file}" }
      @keychain.release.each { |path| @output.puts "removed missing keychain #{path}" }
      problems = @keychain.problems
      if problems.blank?
        @output.puts "The host keychain configuration is healthy."
        return true
      end

      problems.each { |problem| @output.puts "- #{problem}" }
      return needs_attention unless repair

      restore
    end

    private

    def needs_attention
      @output.puts "Run `mise keychain --repair` to restore the login keychain. Repairing may ask you to log out and back in."
      false
    end

    def restore
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
end
