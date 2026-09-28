require "bundler/setup"
Bundler.require(:default)

$root_dir = File.dirname(__FILE__).then { |x| File.dirname(x) }

require_relative "core_extensions"
require_relative "constants"
require_relative "req"
require_relative "cmd"
require_relative "apps"
Dir[File.join($root_dir, "lib", "apps", "**", "*.rb")].sort.each { |path| require path }

require_relative "../patches/base_patch"
File
  .join($root_dir, "patches")
  .then { |x| Dir.glob(File.join(x, "**/*.rb")) }
  .reject { |x| x.end_with?("base_patch.rb") }
  .sort
  .each { |x| require x }
