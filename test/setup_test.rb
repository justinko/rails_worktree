require "test_helper"

class SetupTest < Minitest::Test
  include RepositoryFixture

  def test_prints_main_and_linked_urls_without_starting_a_server
    [ @main, @linked ].each do |path|
      prepare(path)

      output, status = run_script(path, "worktree", "--skip-server")

      assert status.success?, output
      name = service_name(path)
      assert_includes output, "App URL: https://#{name}.localhost"
      calls = calls(path)
      assert_equal [ "portless get #{name} --no-worktree" ], calls.grep(/\Aportless /)
      assert_includes calls, "setup --skip-server"
      refute_includes calls, "rails db:seed"
      assert_equal path == @linked, calls.include?("rails db:prepare")
    end
  end

  def test_linked_output_names_isolated_databases_and_notes
    prepare(@linked, "databases" => %w[queue cable], "notes" => [ "Start jobs: bin/jobs" ])

    output, status = run_script(@linked, "worktree", "--skip-server")

    assert status.success?, output
    identity = RailsWorktree::GitWorktree.new(@linked).identity
    assert_includes output, "Development database: app_#{identity}_development"
    assert_includes output, "Development queue database: app_#{identity}_development_queue"
    assert_includes output, "Development cable database: app_#{identity}_development_cable"
    assert_includes output, "Test database: app_#{identity}_test"
    assert_includes output, "Start jobs: bin/jobs"
  end

  def test_seeds_when_configured_except_on_reset
    prepare(@linked, "seed" => true)

    output, status = run_script(@linked, "worktree", "--skip-server")
    assert status.success?, output
    assert_includes calls(@linked), "rails db:seed"

    File.delete(File.join(@linked, "calls"))
    output, status = run_script(@linked, "worktree", "--reset", "--skip-server")
    assert status.success?, output
    assert_equal [ "portless get #{service_name(@linked)} --no-worktree", "setup --skip-server --reset", "rails db:reset" ], calls(@linked)
  end

  def test_links_the_main_checkout_key_unless_the_environment_provides_one
    prepare(@linked)
    FileUtils.mkdir_p(File.join(@main, "config"))
    File.write(File.join(@main, "config/master.key"), "main-key")

    output, status = run_script(@linked, "worktree", "--skip-server")
    assert status.success?, output
    refute File.symlink?(File.join(@linked, "config/master.key"))

    output, status = run_script(@linked, "worktree", "--skip-server", variables: { "RAILS_MASTER_KEY" => nil })
    assert status.success?, output
    assert File.symlink?(File.join(@linked, "config/master.key"))
  end

  def test_a_required_missing_key_fails_before_running_setup
    prepare(@linked, "require_master_key" => true)

    output, status = run_script(@linked, "worktree", "--skip-server", variables: { "RAILS_MASTER_KEY" => nil })

    refute status.success?
    assert_includes output, "Missing credentials key"
    assert_includes output, "RAILS_MASTER_KEY"
    refute File.exist?(File.join(@linked, "calls"))
  end

  def test_failed_rails_setup_stops_before_seeding_test_preparation_and_server
    prepare(@linked, "seed" => true)
    File.write(File.join(@linked, "bin/setup"), "#!#{RbConfig.ruby}\nwarn 'Setup failed'; exit 23\n")

    output, status = run_script(@linked, "worktree")

    refute status.success?
    assert_includes output, "Setup failed"
    assert_includes output, "bin/setup --skip-server failed"
    assert_empty calls(@linked).grep(/\A(rails|portless [^g])/)
  end

  def test_starts_the_proxied_server_after_database_preparation
    prepare(@linked)

    output, status = run_script(@linked, "worktree")

    assert status.success?, output
    assert_includes calls(@linked), "rails db:prepare"
    assert_equal "portless #{service_name(@linked)} ./bin/rails server", calls(@linked).last
  end

  def test_the_launcher_works_outside_the_checkout_and_forwards_arguments
    prepare(@linked)

    output, status = run_script(@linked, "dev", "--pid", "tmp/server.pid")

    assert status.success?, output
    assert_equal [ "portless #{service_name(@linked)} ./bin/rails server --pid tmp/server.pid" ], calls(@linked)
    assert_equal File.realpath(@linked), File.read(File.join(@linked, "calls.cwd"))
  end

  def test_agent_hook_skips_the_main_checkout
    prepare(@main)

    output, status = run_script(@main, "worktree", "--agent-hook")

    assert status.success?, output
    assert_empty output
    refute File.exist?(File.join(@main, "calls"))
  end

  def test_agent_hook_sets_up_a_linked_worktree_once_with_a_summary_on_stdout
    prepare(@linked)

    stdout, stderr, status = run_script_split(@linked, "worktree", "--agent-hook")

    assert status.success?, stderr
    assert_includes stdout, "App URL: https://#{service_name(@linked)}.localhost"
    assert_includes stderr, "setup output"
    refute_includes stdout, "setup output"
    assert_includes calls(@linked), "rails db:prepare"
    refute calls(@linked).any? { |call| call.end_with?("rails server") }

    File.delete(File.join(@linked, "calls"))
    stdout, _stderr, status = run_script_split(@linked, "worktree", "--agent-hook")
    assert status.success?
    assert_empty stdout
    refute File.exist?(File.join(@linked, "calls"))
  end

  def test_a_manual_setup_satisfies_the_agent_hook
    prepare(@linked)
    output, status = run_script(@linked, "worktree", "--skip-server")
    assert status.success?, output
    File.delete(File.join(@linked, "calls"))

    output, status = run_script(@linked, "worktree", "--agent-hook")

    assert status.success?, output
    refute File.exist?(File.join(@linked, "calls"))
  end

  private
    def prepare(path, settings = {})
      %w[bin config].each { |directory| FileUtils.mkdir_p(File.join(path, directory)) }
      File.write(File.join(path, "config/worktree.yml"), { "name" => "app" }.merge(settings).to_yaml)
      script(path, "worktree", <<~RUBY)
        $LOAD_PATH.unshift #{LIB.inspect}
        require "rails_worktree/setup"
        RailsWorktree::Setup.new(File.expand_path("..", __dir__)).run(ARGV)
      RUBY
      script(path, "dev", <<~RUBY)
        $LOAD_PATH.unshift #{LIB.inspect}
        require "rails_worktree/server"
        RailsWorktree::Server.run(File.expand_path("..", __dir__), ARGV)
      RUBY
      %w[setup rails].each do |command|
        script(path, command, <<~RUBY)
          puts "setup output"
          File.open(ENV.fetch("STARTUP_CALLS"), "a") { |file| file.puts([File.basename($PROGRAM_NAME), *ARGV].join(" ")) }
        RUBY
      end
      FileUtils.mkdir_p(File.join(@directory, "commands"))
      executable = File.join(@directory, "commands/portless")
      File.write(executable, <<~RUBY)
        #!#{RbConfig.ruby}
        File.open(ENV.fetch("STARTUP_CALLS"), "a") { |file| file.puts(["portless", *ARGV].join(" ")) }
        File.write(ENV.fetch("STARTUP_CALLS") + ".cwd", Dir.pwd)
        puts "https://\#{ARGV.fetch(1)}.localhost" if ARGV.first == "get"
      RUBY
      FileUtils.chmod(0o755, executable)
    end

    def script(path, name, source)
      file = File.join(path, "bin", name)
      File.write(file, "#!#{RbConfig.ruby}\n#{source}")
      FileUtils.chmod(0o755, file)
    end

    def environment(path, variables)
      { "RAILS_ENV" => "development", "RAILS_MASTER_KEY" => "provided-key", "PORTLESS_URL" => nil,
        "PATH" => "#{@directory}/commands:#{ENV.fetch("PATH")}", "STARTUP_CALLS" => File.join(path, "calls") }.merge(variables)
    end

    def run_script(path, command, *arguments, variables: {})
      output = IO.popen([ environment(path, variables), RbConfig.ruby, File.join(path, "bin", command), *arguments ],
        chdir: @directory, err: [ :child, :out ], &:read)
      [ output, $? ]
    end

    def run_script_split(path, command, *arguments)
      error = File.join(@directory, "stderr")
      stdout = IO.popen([ environment(path, {}), RbConfig.ruby, File.join(path, "bin", command), *arguments ],
        chdir: @directory, err: error, &:read)
      [ stdout, File.read(error), $? ]
    end

    def calls(path)
      File.exist?(File.join(path, "calls")) ? File.readlines(File.join(path, "calls"), chomp: true) : []
    end

    def service_name(path)
      RailsWorktree::GitWorktree.new(path).service_name("app")
    end
end
