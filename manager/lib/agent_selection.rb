require "time"

class AgentSelection
  MAX_QUOTA_AGE = 300
  MIN_REMAINING = 5

  class << self
    def resolve(runner: nil, model: nil, variant: nil)
      overrides = { runner:, model:, variant: }.select { |_, value| value.present? }
      local = Settings.all.fetch(:agent, {}).slice(:runner, :model, :variant).select do |key, value|
        key == :variant ? value.is_a?(String) : value.present?
      end.merge(overrides)
      candidates = Settings.global[:agentDefaultsBalance]
      return local.slice(:runner, :model, :variant) if candidates.blank?

      compatible = candidates.select { |candidate| local[:runner].blank? || candidate[:runner] == local[:runner] }
      if local[:model].present?
        default = compatible.find { |candidate| candidate[:model] == local[:model] } || compatible.first || {}
      else
        default = compatible.filter_map do |candidate|
          selection = candidate.merge(local.slice(:runner, :variant))
          score = weekly_remaining(selection)
          [ score, candidate ] if score.present?
        end.max_by(&:first)&.last
        raise "No balanced agent provider has fresh usable quota; refresh T3 Usage Limits or set an explicit model" if default.blank?
      end
      default.merge(local).slice(:runner, :model, :variant)
    end

    private

    def stale_quota?(limits)
      Time.now - Time.iso8601(limits.fetch(:checkedAt)) > MAX_QUOTA_AGE
    rescue KeyError, ArgumentError, TypeError, NoMethodError
      false
    end

    def current_quota?(limits)
      return false if limits.blank? || limits[:unavailable].present?

      now = Time.now
      checked = Time.iso8601(limits.fetch(:checkedAt))
      return false unless checked <= now && now - checked <= MAX_QUOTA_AGE

      windows = limits[:windows]
      return false unless windows.is_a?(Array) && windows.present?

      windows.all? { |window| window[:resetsAt].blank? || Time.iso8601(window[:resetsAt]) > now }
    rescue KeyError, ArgumentError, TypeError, NoMethodError
      false
    end

    def weekly_remaining(selection, refresh: true)
      T3Runner.selection(model: selection.fetch(:model), variant: selection[:variant])
      provider = selection.fetch(:model).split("/", 2).first
      instance = T3Runner::PROVIDERS.fetch(provider, provider)
      home = Settings.all.dig(:agent, :t3, :home)
      home = File.expand_path(home.present? ? home : "~/.t3")
      catalog = JSON.parse(File.read(File.join(home, "caches", "#{instance}.json")), symbolize_names: true)
      limits = catalog[:usageLimits]
      unless current_quota?(limits)
        return unless refresh && stale_quota?(limits)

        T3Runner.refresh_provider(instance)
        return weekly_remaining(selection, refresh: false)
      end

      now = Time.now

      windows = limits[:windows]
      return unless windows.is_a?(Array) && windows.present?

      remaining = windows.map do |window|
        used = window[:usedPercent]
        return unless used.is_a?(Numeric) && used.finite? && used.between?(0, 100)
        return if window[:resetsAt].present? && Time.iso8601(window[:resetsAt]) <= now

        quota = 100 - used
        return if window[:kind] == "weekly" ? quota <= 0 : quota < MIN_REMAINING

        [ window[:kind], quota ]
      end
      remaining.select { |kind, _| kind == "weekly" }.map(&:last).min
    rescue JSON::ParserError, SystemCallError, KeyError, ArgumentError, TypeError, NoMethodError, RuntimeError, Timeout::Error, IOError, SocketError, OpenSSL::SSL::SSLError
      nil
    end
  end
end
