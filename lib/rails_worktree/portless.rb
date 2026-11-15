module RailsWorktree
  class Portless
    class Error < RailsWorktree::Error; end

    INSTALLATION = "Portless is required for local development. Install Node.js 24+ and run npm install -g portless@0.15.11."

    def self.url(name)
      url = ENV["PORTLESS_URL"]
      return url unless url.nil? || url.empty?

      output = IO.popen([ "portless", "get", name, "--no-worktree" ], &:read)
      raise Error, "Could not resolve the Portless URL for #{name}. Run portless doctor to check the proxy configuration." unless $?.success?

      output.strip
    rescue Errno::ENOENT
      raise Error, INSTALLATION
    end

    def self.run(name, *command)
      exec "portless", name, *command
    rescue Errno::ENOENT
      raise Error, INSTALLATION
    end
  end
end
