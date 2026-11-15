require "test_helper"

class GitWorktreeTest < Minitest::Test
  include RepositoryFixture
  GitWorktree = RailsWorktree::GitWorktree

  def test_main_checkout_and_git_free_copy_use_normal_defaults
    refute GitWorktree.new(@main).linked?
    refute GitWorktree.new(@directory).linked?
    assert_equal "app", GitWorktree.new(@main).service_name("app")
    assert_equal "app", GitWorktree.new(@directory).service_name("app")
  end

  def test_linked_worktrees_have_bounded_identities_independent_of_their_branch
    worktree = GitWorktree.new(@linked)
    assert worktree.linked?
    assert_match(/\A[a-z0-9_]{1,12}_[a-f0-9]{8}\z/, worktree.identity)
    name = worktree.service_name("app")
    assert_equal "#{worktree.identity.tr("_", "-")}.app", name

    git(@linked, "switch", "--quiet", "-c", "another-branch")
    assert_equal worktree.identity, GitWorktree.new(@linked).identity
    git(@linked, "switch", "--quiet", "--detach")
    assert_equal name, GitWorktree.new(@linked).service_name("app")
  end

  def test_identical_directory_names_differ_and_symlinks_keep_the_same_identity
    other = File.join(@directory, "other", File.basename(@linked))
    git(@main, "worktree", "add", "--quiet", "--detach", other)
    refute_equal GitWorktree.new(@linked).identity, GitWorktree.new(other).identity

    alias_path = File.join(@directory, "alias")
    File.symlink(@linked, alias_path)
    assert_equal GitWorktree.new(@linked).identity, GitWorktree.new(alias_path).identity
  end

  def test_long_and_unusual_checkout_names_produce_valid_database_identifiers
    path = File.join(@directory, "雪 !\n" + "long-name" * 15)
    git(@main, "worktree", "add", "--quiet", "--detach", path)
    worktree = GitWorktree.new(path)

    assert_match(/\A[a-z0-9_]+\z/, worktree.identity)
    assert_operator "codetryout_#{worktree.identity}_development_123456".bytesize, :<, 63
    assert_match(/\A[a-z0-9-]+\.app\z/, worktree.service_name("app"))
  end

  def test_truncated_identities_have_no_leading_or_trailing_separators
    %w[worktree-db-child abcdefghijk-feature].each do |name|
      path = File.join(@directory, name)
      FileUtils.mkdir_p(path)

      assert_match(/\A[a-z0-9]+(?:[-_.][a-z0-9]+)*\z/, "app-demo-#{GitWorktree.new(path).identity}")
    end
  end

  def test_links_a_missing_file_from_the_main_checkout_and_can_be_repeated
    [ @main, @linked ].each { |path| FileUtils.mkdir_p(File.join(path, "config")) }
    File.write(File.join(@main, "config/master.key"), "main-key")
    worktree = GitWorktree.new(@linked)

    assert worktree.link_file("config/master.key")
    assert File.symlink?(File.join(@linked, "config/master.key"))
    assert_equal "main-key", File.read(File.join(@linked, "config/master.key"))
    refute worktree.link_file("config/master.key")
  end

  def test_preserves_a_local_file_and_a_broken_symlink
    [ @main, @linked ].each { |path| FileUtils.mkdir_p(File.join(path, "config")) }
    File.write(File.join(@main, "config/master.key"), "main-key")
    destination = File.join(@linked, "config/master.key")
    File.write(destination, "local-key")
    worktree = GitWorktree.new(@linked)

    refute worktree.link_file("config/master.key")
    assert_equal "local-key", File.read(destination)
    File.unlink(destination)
    File.symlink("missing-key", destination)
    refute worktree.link_file("config/master.key")
    assert_equal "missing-key", File.readlink(destination)
  end

  def test_a_missing_source_does_not_create_a_link
    refute GitWorktree.new(@linked).link_file("config/master.key")
    refute File.symlink?(File.join(@linked, "config/master.key"))
  end

  def test_worktrees_of_a_bare_repository_do_not_assume_a_main_checkout
    bare = File.join(@directory, "bare.git")
    git(@directory, "clone", "--quiet", "--bare", @main, bare)
    path = File.join(@directory, "bare-source-checkout")
    git(bare, "worktree", "add", "--quiet", "--detach", path)
    worktree = GitWorktree.new(path)

    assert worktree.linked?
    refute worktree.link_file("config/master.key")
  end

  def test_service_names_replace_underscores_for_hostnames
    config = RailsWorktree::Config.new(@main, "name" => "code_tryout")
    assert_equal "code-tryout", config.service_name(GitWorktree.new(@main))
    assert_equal "code_tryout_development", config.database("development")
  end

  def test_git_path_is_specific_to_each_worktree
    refute_equal GitWorktree.new(@main).git_path("marker"), GitWorktree.new(@linked).git_path("marker")
    assert File.absolute_path?(GitWorktree.new(@linked).git_path("marker"))
  end
end
