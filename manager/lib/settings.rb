class Settings
  class << self
    attr_writer :path

    def path = @path || File.expand_path("../../config.json", __dir__)

    def all
      @all ||= JSON.parse(File.read(path), symbolize_names: true)
    end

    def reset
      @path = nil
      @all = nil
    end
  end
end
