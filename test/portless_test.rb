require "test_helper"

class PortlessTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("portless-test")
    @arguments = File.join(@directory, "arguments")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_an_injected_public_url_does_not_need_the_executable
    output, status = portless_process('puts RailsWorktree::Portless.url("app")', "PORTLESS_URL" => "https://app.test:8443")

    assert status.success?, output
    assert_equal "https://app.test:8443", output.strip
  end

  def test_url_discovery_uses_the_explicit_service_name_without_a_branch_prefix
    executable <<~RUBY
      File.write(ENV.fetch("PORTLESS_TEST_ARGUMENTS"), ARGV.join("\\n"))
      puts "https://review.app.test:8443"
    RUBY

    output, status = portless_process('puts RailsWorktree::Portless.url("review.app")', "PORTLESS_URL" => "")

    assert status.success?, output
    assert_equal "https://review.app.test:8443", output.strip
    assert_equal [ "get", "review.app", "--no-worktree" ], File.readlines(@arguments, chomp: true)
  end

  def test_failed_url_discovery_does_not_return_the_command_output_as_a_url
    executable 'puts "https://stale.localhost"; exit 23'

    output, status = portless_process('puts RailsWorktree::Portless.url("app")')

    refute status.success?
    assert_includes output, "Could not resolve the Portless URL for app"
    assert_includes output, "portless doctor"
  end

  def test_a_missing_executable_explains_installation
    [ 'RailsWorktree::Portless.url("app")', 'RailsWorktree::Portless.run("app", "./bin/rails", "server")' ].each do |source|
      output, status = portless_process(source)

      refute status.success?
      assert_includes output, "Node.js 24+"
      assert_includes output, "npm install -g portless@0.15.11"
    end
  end

  def test_startup_preserves_arguments_and_the_child_exit_status
    executable <<~RUBY
      File.write(ENV.fetch("PORTLESS_TEST_ARGUMENTS"), ARGV.join("\\n"))
      exit 23
    RUBY

    output, status = portless_process('RailsWorktree::Portless.run("review.app", "./bin/rails", "server", "--pid", "tmp/server pid")')

    assert_equal 23, status.exitstatus, output
    assert_equal [ "review.app", "./bin/rails", "server", "--pid", "tmp/server pid" ], File.readlines(@arguments, chomp: true)
  end

  private
    def executable(source)
      path = File.join(@directory, "portless")
      File.write(path, "#!#{RbConfig.ruby}\n#{source}\n")
      FileUtils.chmod(0o755, path)
    end

    def portless_process(source, variables = {})
      environment = { "PATH" => @directory, "PORTLESS_URL" => nil, "PORTLESS_TEST_ARGUMENTS" => @arguments }.merge(variables)
      output = IO.popen([ environment, RbConfig.ruby, "-I", LIB, "-r", "rails_worktree", "-e", source ],
        err: [ :child, :out ], &:read)
      [ output, $? ]
    end
end
