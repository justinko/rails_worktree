require "json"
require "rails/generators"

module RailsWorktree
  module Generators
    # Adds worktree setup for Orca, Claude Code, and Codex to a Rails app.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :app_name, type: :string, desc: "Database prefix and Portless service name (defaults to the directory name)"

      # CLAUDE_PROJECT_DIR names the main checkout, so find the session's worktree from the hook's cwd.
      CLAUDE_HOOK = %q(ruby -rjson -e 'root = IO.popen(["git", "-C", JSON.parse($stdin.read).fetch("cwd"), "rev-parse", "--show-toplevel"], &:read).chomp; ) +
        %q(script = File.join(root, "bin/worktree"); exec(script, "--agent-hook") if $?.success? && File.executable?(script)')

      def worktree_config
        template "worktree.yml.tt", "config/worktree.yml"
      end

      def bin_scripts
        template "bin/worktree.tt", "bin/worktree"
        template "bin/dev.tt", "bin/dev"
        chmod "bin/worktree", 0o755
        chmod "bin/dev", 0o755
      end

      def orca
        template "orca.yaml.tt", "orca.yaml"
      end

      def codex
        template "environment.toml.tt", ".codex/environments/environment.toml"
      end

      def claude
        template "worktreeinclude.tt", ".worktreeinclude"
        settings_path = File.join(destination_root, ".claude/settings.json")
        settings = File.exist?(settings_path) ? JSON.parse(File.read(settings_path)) : {}
        session_start = ((settings["hooks"] ||= {})["SessionStart"] ||= [])
        return say_status(:identical, ".claude/settings.json", :blue) if session_start.to_s.include?("--agent-hook")

        session_start << { "matcher" => "startup",
          "hooks" => [ { "type" => "command", "command" => CLAUDE_HOOK, "timeout" => 900 } ] }
        create_file ".claude/settings.json", JSON.pretty_generate(settings) + "\n", force: true
      end

      def gitignore
        return unless File.exist?(File.join(destination_root, ".gitignore"))
        return if File.read(File.join(destination_root, ".gitignore")).include?("/.claude/worktrees/")

        append_to_file ".gitignore", "\n# Claude Code worktrees.\n/.claude/worktrees/\n"
      end

      def instructions
        say <<~TEXT

          Next steps:
            config/database.yml (development and test):
              database: <%= RailsWorktree.database("development") %>
              database: <%= RailsWorktree.database("development", "queue") %>
              database: <%= RailsWorktree.database("test") %>
            Cookie names that must differ per worktree:
              config.x.authentication_cookie_name = RailsWorktree.suffixed(:session_id)
            Remove config.action_mailer.default_url_options from config/environments/development.rb;
            development URLs come from Portless (Node.js 24+, npm install -g portless@0.15.11).
        TEXT
      end

      private
        def app_name
          options[:app_name] || File.basename(destination_root).downcase.gsub(/[^a-z0-9]+/, "_")
        end
    end
  end
end
