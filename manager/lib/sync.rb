class Sync
  class << self
    def call
      Linear.sync_statuses
      Linear.sync_tags
      Linear.sync_git_automations
    end
  end
end
