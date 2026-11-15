require "test_helper"

class RailtieTest < Minitest::Test
  include RepositoryFixture

  def setup
    super
    [ @main, @linked ].each { |path| write_app(path) }
  end

  def test_main_checkout_keeps_normal_names
    result = boot(@main)

    assert_equal({ "primary" => "app_development", "queue" => "app_development_queue" }, result.fetch("development"))
    assert_equal "app_test", result.fetch("test")
    assert_equal "session_id", result.fetch("cookie")
    assert_nil result.fetch("worktree")
  end

  def test_linked_development_isolates_databases_cookies_and_urls
    identity = RailsWorktree::GitWorktree.new(@linked).identity
    result = boot(@linked, "PORTLESS_URL" => "https://review.example.test:8443")

    assert_equal({ "primary" => "app_#{identity}_development", "queue" => "app_#{identity}_development_queue" },
      result.fetch("development"))
    assert_equal "app_#{identity}_test", result.fetch("test")
    assert_equal "session_id_#{identity}", result.fetch("cookie")
    assert_equal "_app_session_#{identity}", result.fetch("session_key")
    assert_equal identity, result.fetch("worktree")
    expected = { "host" => "review.example.test", "protocol" => "https", "port" => 8443 }
    assert_equal expected, result.fetch("mailer_url_options")
    assert_equal expected, result.fetch("route_url_options")
    assert_includes result.fetch("hosts"), "review.example.test"
  end

  def test_test_environment_isolates_databases_without_renaming_cookies
    identity = RailsWorktree::GitWorktree.new(@linked).identity
    result = boot(@linked, "RAILS_ENV" => "test")

    assert_equal "app_#{identity}_test", result.fetch("test")
    assert_equal "session_id", result.fetch("cookie")
  end

  def test_conflicting_database_urls_fail_without_printing_credentials
    identity = RailsWorktree::GitWorktree.new(@linked).identity
    [ { "DATABASE_URL" => "sqlite3:shared?password=private-marker" },
      { "QUEUE_DATABASE_URL" => "sqlite3:shared?database_tasks=false" } ].each do |variables|
      output, status = boot_process(@linked, variables)

      refute status.success?
      assert_match(/Worktree database must be app_#{identity}_development/, output)
      refute_includes output, "private-marker"
    end
  end

  def test_boots_without_a_config_file_so_the_generator_can_run
    File.delete(File.join(@main, "config/worktree.yml"))
    output, status = boot_process(@main, {})

    assert status.success?, output
    assert_includes output, "config/worktree.yml is missing"
    assert_equal "dummy_test", JSON.parse(output.lines.last).fetch("test")
  end

  def test_production_does_not_inspect_git
    result = boot(@linked, "RAILS_ENV" => "production", "GIT_DIR" => "/nonexistent")

    assert_nil result.fetch("worktree")
    assert_equal "session_id", result.fetch("cookie")
  end

  private
    def write_app(path)
      FileUtils.mkdir_p(File.join(path, "config"))
      File.write(File.join(path, "config/worktree.yml"), "name: app\n")
      File.write(File.join(path, "config/database.yml"), <<~YAML)
        development:
          primary:
            adapter: sqlite3
            database: <%= RailsWorktree.database("development") %>
          queue:
            adapter: sqlite3
            database: <%= RailsWorktree.database("development", "queue") %>
        test:
          adapter: sqlite3
          database: <%= RailsWorktree.database("test") %>
        production:
          adapter: sqlite3
          database: app_production
      YAML
    end

    def boot(path, variables = {})
      output, status = boot_process(path, variables)
      assert status.success?, output
      JSON.parse(output.lines.last)
    end

    def boot_process(path, variables)
      environment = { "RAILS_ENV" => "development", "DATABASE_URL" => nil, "QUEUE_DATABASE_URL" => nil,
        "PORTLESS_URL" => "https://app.localhost", "SECRET_KEY_BASE" => "test" }.merge(variables)
      script = <<~'RUBY'
        require "rails"
        require "active_record/railtie"
        require "action_controller/railtie"
        require "action_mailer/railtie"
        require "rails_worktree"

        class Dummy < Rails::Application
          config.root = ARGV.fetch(0)
          config.load_defaults Rails::VERSION::STRING.to_f
          config.eager_load = false
          config.logger = Logger.new(nil)
          config.x.authentication_cookie_name = RailsWorktree.suffixed(:session_id)
        end
        Rails.application.initialize!
        ActiveRecord::Base

        configurations = ActiveRecord::Base.configurations
        puts JSON.generate(
          "development" => configurations.configs_for(env_name: "development").to_h { |c| [ c.name, c.database ] },
          "test" => configurations.configs_for(env_name: "test").first.database,
          "cookie" => Rails.application.config.x.authentication_cookie_name.to_s,
          "session_key" => Rails.application.config.session_options[:key],
          "worktree" => Rails.application.config.x.worktree&.identity,
          "mailer_url_options" => ActionMailer::Base.default_url_options,
          "route_url_options" => Rails.application.routes.default_url_options,
          "hosts" => Rails.application.config.hosts.map(&:to_s))
      RUBY
      output = IO.popen([ environment, RbConfig.ruby, "-I", LIB, "-rbundler/setup", "-e", script, path ],
        chdir: File.expand_path("..", __dir__), err: [ :child, :out ], &:read)
      [ output, $? ]
    end
end
