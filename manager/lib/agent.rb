class Agent
  ROOT = File.expand_path("../..", __dir__)
  URL = "http://127.0.0.1:57123"

  class << self
    def start(prompt, directory: ROOT, model: nil, variant: nil)
      case Settings.all.dig(:agent, :runner)
      when "openchamber"
        openchamber(prompt, directory, model:, variant:)
      else
        raise "Unknown agent runner #{Settings.all.dig(:agent, :runner)}"
      end
    end

    def openchamber(prompt, directory, model:, variant:)
      model = Settings.all.dig(:agent, :model) if model.blank?
      variant = Settings.all.dig(:agent, :variant) if variant.blank?
      payload = {
        directory:,
        prompt:,
        model:,
      }
      payload[:variant] = variant if variant.present?
      Req.call(
        url: "#{URL}/api/openchamber/sessions",
        method: :post,
        payload:,
      )
    end
  end
end
