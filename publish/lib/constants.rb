class Constants
  class << self
    attr_writer :config_path

    def local_root = File.dirname(File.dirname(File.dirname(__FILE__)))
    def config_path = @config_path || File.join(local_root, "config.json")
    def config = @config ||= JSON.parse(File.read(config_path), symbolize_names: true)
  end
end
