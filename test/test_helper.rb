$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "minitest/autorun"
require "fileutils"
require "json"
require "rbconfig"
require "tmpdir"
require "rails_worktree"
require "yaml"

LIB = File.expand_path("../lib", __dir__)

# Temporary main checkout with one linked worktree.
module RepositoryFixture
  def setup
    @directory = File.realpath(Dir.mktmpdir("rails-worktree-test"))
    @main = File.join(@directory, "main")
    @linked = File.join(@directory, "feature worktree")
    FileUtils.mkdir_p(@main)
    git(@main, "init", "--quiet", "--initial-branch=main")
    git(@main, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
      "commit", "--quiet", "--allow-empty", "-m", "Initial commit")
    git(@main, "worktree", "add", "--quiet", "--detach", @linked)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def git(path, *arguments)
    system("git", "-C", path, *arguments, out: File::NULL, err: File::NULL, exception: true)
  end
end
