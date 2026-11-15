require_relative "../rails_worktree"

module RailsWorktree
  # Starts Rails behind Portless under this checkout's service name (bin/dev).
  module Server
    def self.run(root, arguments)
      Dir.chdir(root) do
        config = Config.load(root)
        Portless.run(GitWorktree.new(root).service_name(config.name), "./bin/rails", "server", *arguments)
      end
    rescue Error => error
      abort error.message
    end
  end
end
