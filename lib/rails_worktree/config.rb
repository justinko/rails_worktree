require "yaml"

module RailsWorktree
  # Settings shared by the bin scripts and the Railtie. Plain YAML so setup can read it before
  # Bundler has loaded Rails.
  class Config
    FILE = "config/worktree.yml"
    MASTER_KEY = "config/master.key"

    attr_reader :root, :name, :databases, :link_files, :notes

    def self.load(root)
      path = File.join(root, FILE)
      raise Error, "Missing #{FILE}. Run bin/rails generate rails_worktree:install." unless File.file?(path)

      new(root, YAML.safe_load_file(path) || {})
    end

    def initialize(root, settings = {})
      @root = root
      @name = settings.fetch("name") { raise Error, "#{FILE} must define name" }.to_s
      raise Error, "#{FILE} name must contain only lowercase letters, digits, and underscores" unless @name.match?(/\A[a-z][a-z0-9_]*\z/)

      @databases = Array(settings.fetch("databases", []))
      @link_files = Array(settings.fetch("link_files", [ MASTER_KEY ]))
      @require_master_key = settings.fetch("require_master_key", false)
      @seed = settings.fetch("seed", false)
      @notes = Array(settings.fetch("notes", []))
    end

    # Portless hostnames cannot contain underscores.
    def service_name(worktree)
      worktree.service_name(name.tr("_", "-"))
    end

    def require_master_key? = @require_master_key
    def seed? = @seed

    # Database name for an environment and role, isolated by worktree identity when given one.
    def database(environment, role = nil, identity: nil)
      [ name, identity, environment, (role.to_s unless role.nil? || role.to_s == "primary") ].compact.join("_")
    end
  end
end
