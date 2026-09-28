require "bundler/setup"
Bundler.require(:default)

require "json"

require_relative "core_extensions"
require_relative "settings"
require_relative "req"
require_relative "linear"
require_relative "agent"
require_relative "worktree"
require_relative "trigger"
require_relative "trigger_all"
require_relative "linear_sync"
require_relative "linear_sync_all"
require_relative "spawn"
