require "rails/railtie"

module RailsWorktree
  class Railtie < Rails::Railtie
    config.rails_worktree = ActiveSupport::OrderedOptions.new
    config.rails_worktree.portless = true
    config.rails_worktree.session_store = true

    config.before_initialize do |app|
      options = app.config.rails_worktree
      app.config.x.worktree = RailsWorktree.current

      if Rails.env.development?
        if RailsWorktree.current && options.session_store
          app.config.session_store :cookie_store, key: "_#{RailsWorktree.config.name}_session_#{RailsWorktree.identity}"
        end

        if options.portless
          url_options = RailsWorktree.url_options
          app.config.action_mailer.default_url_options = url_options if app.config.respond_to?(:action_mailer)
          app.routes.default_url_options = url_options
          app.config.hosts << url_options.fetch(:host)
        end
      end
    end

    initializer "rails_worktree.database_guard", before: "active_record.initialize_database" do |app|
      if RailsWorktree.current
        ActiveSupport.on_load(:active_record) do
          configurations = ActiveRecord::DatabaseConfigurations.new(app.config.database_configuration)
          configurations.configs_for(include_hidden: true).each do |database|
            next unless ISOLATED_ENVIRONMENTS.include?(database.env_name)

            expected = RailsWorktree.database(database.env_name, database.name)
            unless database.database == expected
              raise ArgumentError, "Worktree database must be #{expected}. Remove database names from connection URLs, or unset the variables."
            end
          end
        end
      end
    end

    generators do
      require_relative "../generators/rails_worktree/install_generator"
    end
  end
end
