require "fileutils"
require_relative "../rails_worktree"

module RailsWorktree
  # Prepares a checkout for development (bin/worktree). Orca, Codex, and Claude Code run it when
  # they create a worktree; it is also safe to rerun by hand.
  #
  #   --skip-server  prepare only, do not exec bin/dev
  #   --reset        rebuild development and test databases instead of seeding
  #   --agent-hook   for agent session hooks: only act in a linked worktree that has not been set
  #                  up yet, send progress to stderr and a short summary to stdout
  class Setup
    MARKER = "rails_worktree-setup"

    attr_reader :root, :config, :worktree, :environment

    def initialize(root, environment: ENV)
      @root = File.expand_path(root)
      @environment = environment
    end

    def run(arguments)
      arguments = arguments.dup
      agent_hook = arguments.delete("--agent-hook")
      reset = arguments.include?("--reset")
      skip_server = agent_hook || arguments.include?("--skip-server")

      Dir.chdir(root) do
        @config = Config.load(root)
        @worktree = GitWorktree.new(root)
        return if agent_hook && !needs_agent_setup?

        summary = $stdout
        $stdout = $stderr if agent_hook

        prepare(reset:)
        report(summary)

        unless skip_server
          puts "\n== Starting development server =="
          $stdout.flush
          exec "bin/dev"
        end
      ensure
        $stdout = STDOUT
      end
    rescue Error => error
      abort error.message
    end

    private
      def development?
        environment.fetch("RAILS_ENV", environment.fetch("RACK_ENV", "development")) == "development"
      end

      def linked_development?
        development? && worktree.linked?
      end

      def needs_agent_setup?
        linked_development? && !File.exist?(worktree.git_path(MARKER))
      end

      def prepare(reset:)
        link_files if development?
        @app_url = Portless.url(config.service_name(worktree)) if development?

        # Child processes inherit file descriptors, so send their output where ours goes.
        out = $stdout.equal?($stderr) ? :err : :out
        setup_environment = linked_development? ? { "SKIP_TEST_DATABASE" => "1" } : {}
        command(setup_environment, "bin/setup", "--skip-server", *("--reset" if reset), out:)
        command("bin/rails", "db:seed", out:) if config.seed? && !reset
        command({ "RAILS_ENV" => "test" }, "bin/rails", reset ? "db:reset" : "db:prepare", out:) if linked_development?

        FileUtils.touch(worktree.git_path(MARKER)) if linked_development?
      end

      def link_files
        key_from_environment = !environment["RAILS_MASTER_KEY"].to_s.empty?
        config.link_files.each do |file|
          next if file == Config::MASTER_KEY && key_from_environment

          worktree.link_file(file)
        end

        if config.require_master_key? && !key_from_environment && !File.file?(Config::MASTER_KEY)
          raise Error, "Missing credentials key. Restore #{Config::MASTER_KEY} in the main checkout and rerun bin/worktree, " \
            "or set RAILS_MASTER_KEY. Existing worktree keys and symlinks are never overwritten."
        end
      end

      def command(*arguments, out:)
        system(*arguments, out:) || raise(Error, "#{arguments.grep(String).join(" ")} failed")
      end

      def report(io)
        return unless development?

        identity = worktree.identity if worktree.linked?
        io.puts
        io.puts "Development database: #{config.database("development", identity:)}"
        config.databases.each do |role|
          io.puts "Development #{role} database: #{config.database("development", role, identity:)}"
        end
        io.puts "Test database: #{config.database("test", identity:)}"
        io.puts "App URL: #{@app_url}"
        io.puts "Start Rails: bin/dev"
        config.notes.each { |note| io.puts note }
      end
  end
end
