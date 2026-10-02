class Settings
  class << self
    attr_writer :path, :global_path

    def path = @path || File.expand_path("../../config.json", __dir__)
    def global_path = @global_path || File.expand_path("~/.config/codemoto/config.json")

    def all
      @all ||= begin
        local = JSON.parse(File.read(path), symbolize_names: true)
        local.merge(agent: local.fetch(:agent, {}))
      end
    end

    def global
      @global ||= begin
        config = File.file?(global_path) ? JSON.parse(File.read(global_path), symbolize_names: true) : {}
        raise "Code Moto global config must be an object: #{global_path}" unless config.is_a?(Hash)
        if config.key?(:agentDefaultsBalance)
          candidates = config[:agentDefaultsBalance]
          unless candidates.is_a?(Array) && candidates.present? && candidates.all? do |candidate|
            candidate.is_a?(Hash) && candidate[:runner] == "t3" &&
              candidate[:model].is_a?(String) && candidate[:model].match?(/\A[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\z/) &&
              (!candidate.key?(:variant) || candidate[:variant].is_a?(String))
          end
            raise "Code Moto agentDefaultsBalance must be a nonempty array of T3 runner/model/variant selections: #{global_path}"
          end
        end
        config
      end
    rescue JSON::ParserError
      raise "Invalid JSON in Code Moto global config: #{global_path}"
    end

    def service_account_token
      token = global[:"1passwordServiceAccountToken"]
      unless token.is_a?(String) && token.present?
        raise "Set 1passwordServiceAccountToken in #{global_path} before refreshing secrets"
      end
      token
    end

    def reset
      @path = nil
      @global_path = nil
      @all = nil
      @global = nil
    end
  end
end
