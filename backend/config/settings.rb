require "json"

class Settings
  class << self
    def path = File.expand_path("../../config.json", __dir__)
    def all = @all ||= JSON.parse(File.read(path), symbolize_names: true)

    def development_url
      "https://#{ENV["LOCAL_DOMAIN"].presence || all.fetch(:domain).split(".").first}.localhost"
    end
  end
end
