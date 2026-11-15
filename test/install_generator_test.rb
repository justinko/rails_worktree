require "test_helper"
require "rails"
require "generators/rails_worktree/install_generator"

class InstallGeneratorTest < Minitest::Test
  def setup
    @root = File.join(Dir.mktmpdir("generator-test"), "my-app")
    FileUtils.mkdir_p(File.join(@root, ".claude"))
    File.write(File.join(@root, ".gitignore"), "/log/*\n")
    File.write(File.join(@root, ".claude/settings.json"), JSON.generate("permissions" => { "deny" => [ "x" ] }))
  end

  def teardown
    FileUtils.remove_entry(File.dirname(@root))
  end

  def test_writes_setup_for_orca_claude_and_codex
    generate

    assert_equal "my_app", YAML.safe_load_file(file("config/worktree.yml")).fetch("name")
    assert File.executable?(file("bin/worktree"))
    assert File.executable?(file("bin/dev"))
    assert_includes File.read(file("orca.yaml")), "bin/worktree --skip-server"
    assert_includes File.read(file(".codex/environments/environment.toml")), "bin/worktree --skip-server"
    assert_includes File.read(file(".worktreeinclude")), "config/master.key"
    assert_includes File.read(file(".gitignore")), "/.claude/worktrees/"

    settings = JSON.parse(File.read(file(".claude/settings.json")))
    assert_equal [ "x" ], settings.dig("permissions", "deny")
    hook = settings.dig("hooks", "SessionStart", 0)
    assert_equal "startup", hook.fetch("matcher")
    assert_includes hook.dig("hooks", 0, "command"), "--agent-hook"
  end

  def test_rerunning_does_not_duplicate_hooks_or_gitignore_entries
    generate
    generate

    settings = JSON.parse(File.read(file(".claude/settings.json")))
    assert_equal 1, settings.dig("hooks", "SessionStart").size
    assert_equal 1, File.read(file(".gitignore")).scan("/.claude/worktrees/").size
  end

  def test_app_name_option
    generate("--app-name", "kur")

    assert_equal "kur", YAML.safe_load_file(file("config/worktree.yml")).fetch("name")
    assert_includes File.read(file(".codex/environments/environment.toml")), 'name = "kur"'
  end

  def test_claude_hook_runs_the_session_worktree_setup
    generate
    command = JSON.parse(File.read(file(".claude/settings.json"))).dig("hooks", "SessionStart", 0, "hooks", 0, "command")
    system("git", "init", "--quiet", @root, exception: true)
    File.write(file("bin/worktree"), "#!/bin/sh\necho \"ran $1 in $(pwd)\"\n")
    FileUtils.mkdir_p(file("app"))

    output = IO.popen([ "sh", "-c", command ], "r+", chdir: Dir.tmpdir) do |io|
      io.write(JSON.generate("cwd" => file("app")))
      io.close_write
      io.read
    end

    assert_includes output, "ran --agent-hook"
  end

  private
    def generate(*arguments)
      capture_io { RailsWorktree::Generators::InstallGenerator.start(arguments, destination_root: @root) }
    end

    def file(path)
      File.join(@root, path)
    end
end
