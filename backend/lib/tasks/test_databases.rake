namespace :db do
  namespace :test do
    desc "Drop test databases left by removed worktrees"
    task prune: :load_config do
      checkouts = `git -C #{Settings.root.shellescape} worktree list --porcelain`
        .lines
        .select { |x| x.start_with?("worktree ") }
        .map { |x| x.delete_prefix("worktree ").chomp }
      next if checkouts.blank?

      config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary")
      ActiveRecord::Base.establish_connection(config.configuration_hash.merge(database: "postgres"))
      connection = ActiveRecord::Base.lease_connection
      databases = connection.select_values("SELECT datname FROM pg_database")
      Settings.stale_test_databases(databases, checkouts).each do |name|
        puts "Dropping #{name}"
        connection.drop_database(name)
      end
    end
  end
end
