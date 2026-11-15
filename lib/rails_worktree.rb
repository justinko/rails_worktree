require "uri"
require_relative "rails_worktree/version"

module RailsWorktree
  class Error < StandardError; end

  ISOLATED_ENVIRONMENTS = %w[development test].freeze
end

require_relative "rails_worktree/git_worktree"
require_relative "rails_worktree/portless"
require_relative "rails_worktree/config"

module RailsWorktree
  class << self
    def config
      @config ||= if File.file?(Rails.root.join(Config::FILE))
        Config.load(Rails.root.to_s)
      else
        # Lets the app boot so the install generator can write the file.
        name = (Rails.application.class.module_parent_name || Rails.application.class.name).underscore
        warn "rails_worktree: #{Config::FILE} is missing; using #{name.inspect}. Run bin/rails generate rails_worktree:install."
        Config.new(Rails.root.to_s, "name" => name)
      end
    end

    # The linked worktree for this checkout in development and test, otherwise nil.
    # Production never inspects Git.
    def current
      return @current if defined?(@current)

      @current = if ISOLATED_ENVIRONMENTS.include?(Rails.env)
        worktree = GitWorktree.new(Rails.root.to_s)
        worktree if worktree.linked?
      end
    end

    def identity
      current&.identity
    end

    def database(environment, role = nil)
      config.database(environment, role, identity: (identity if ISOLATED_ENVIRONMENTS.include?(environment.to_s)))
    end

    # Appends the worktree identity to cookie names in linked development checkouts.
    def suffixed(name)
      Rails.env.development? && current ? "#{name}_#{identity}" : name
    end

    def service_name
      config.service_name(current || GitWorktree.new(Rails.root.to_s))
    end

    def app_url
      @app_url ||= URI.parse(Portless.url(service_name))
    end

    def url_options
      { host: app_url.host, protocol: app_url.scheme, port: app_url.port }
    end

    def reset!
      remove_instance_variable(:@current) if defined?(@current)
      @config = @app_url = nil
    end
  end
end

require_relative "rails_worktree/railtie" if defined?(Rails::Railtie)
