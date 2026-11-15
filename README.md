# rails_worktree

Run many checkouts of one Rails app side by side. Each Git worktree gets its own databases, session
cookies, and HTTPS URL, and is set up automatically when Orca, Claude Code, or
Codex creates it.

- **Databases**: a linked worktree uses `<name>_<identity>_development` and `<name>_<identity>_test`
  (plus roles such as `_queue`). The identity comes from the checkout's real path, not the branch.
  The main checkout keeps the usual names. Connection URLs that point a worktree at another
  checkout's database fail at boot.
- **Cookies**: in linked development checkouts, the session cookie key and any cookie name passed
  through `RailsWorktree.suffixed` get the identity appended.
- **URLs**: `bin/dev` runs Rails through [Portless](https://portless.sh), giving
  `https://<name>.localhost` for the main checkout and `https://<identity>.<name>.localhost` for
  worktrees. Development sets `config.hosts`, mailer and route URL options from it.
- **Setup**: `bin/worktree` links gitignored files (such as `config/master.key`) from the main
  checkout, runs `bin/setup`, prepares the isolated test database, and optionally seeds.

Production is unaffected and never inspects Git.

## Installation

Requires Node.js 24+ and Portless: `npm install -g portless@0.15.11`.

```ruby
# Gemfile
gem "rails_worktree", github: "justinko/rails_worktree"
```

```bash
bundle install
bin/rails generate rails_worktree:install --app-name myapp
```

The generator writes:

| File | Purpose |
| --- | --- |
| `config/worktree.yml` | App name and setup options |
| `bin/worktree` | Setup script |
| `bin/dev` | Starts Rails through Portless |
| `orca.yaml` | Orca runs `bin/worktree --skip-server` and waits for it before starting the agent |
| `.codex/environments/environment.toml` | Codex runs `bin/worktree --skip-server` when it creates a worktree |
| `.claude/settings.json` | A `SessionStart` hook runs `bin/worktree --agent-hook` |
| `.worktreeinclude` | Claude Code copies `config/master.key` into its worktrees |

Then use the helpers in `config/database.yml` for development and test:

```yaml
development:
  primary:
    <<: *default
    database: <%= RailsWorktree.database("development") %>
  queue:
    <<: *default
    database: <%= RailsWorktree.database("development", "queue") %>
    migrations_paths: db/queue_migrate
test:
  <<: *default
  database: <%= RailsWorktree.database("test") %>
```

Remove `config.action_mailer.default_url_options` from `config/environments/development.rb`.
If you use Rails authentication cookies, isolate them too:

```ruby
config.x.authentication_cookie_name = RailsWorktree.suffixed(:session_id)
```

## Configuration

```yaml
# config/worktree.yml
name: myapp                  # database prefix and Portless service name
databases: [queue, cable]    # extra development databases, listed in setup output
link_files: [config/master.key]
require_master_key: false    # fail setup when no key is linked or set in RAILS_MASTER_KEY
seed: false                  # run db:seed after setup (skipped with --reset)
notes: ["Start jobs in another terminal: bin/jobs"]
```

Railtie options:

```ruby
config.rails_worktree.portless = false       # keep your own development URL settings
config.rails_worktree.session_store = false  # keep your own session store
```

Other helpers: `RailsWorktree.current` (the linked `GitWorktree` or nil), `RailsWorktree.identity`,
`RailsWorktree.app_url` (a `URI`), `RailsWorktree.url_options`.

## bin/worktree

```
bin/worktree                 set up, then start bin/dev
bin/worktree --skip-server   set up only
bin/worktree --reset         rebuild development and test databases
bin/worktree --agent-hook    set up a linked worktree once; no-op elsewhere
```

`--agent-hook` sends progress to stderr and a summary (databases, URL) to stdout, which Claude
Code adds to the session context. A marker in the worktree's Git directory records a successful
setup, so worktrees already set up by Orca, Codex, or by hand are not set up again.

## Agent notes

- **Claude Code**: `SessionStart` covers `claude --worktree` sessions. It does not run when a
  session moves into a worktree mid-run or for subagent worktrees; run `bin/worktree --skip-server`
  there. Add `.claude/worktrees/` to `.gitignore` (the generator does).
- **Codex**: worktrees live in `~/.codex/worktrees` on a detached `HEAD`. The setup script finds the
  main checkout through `git worktree list`.
- **Orca**: `setupAgentStartupPolicy: wait-for-setup` holds the agent until setup succeeds.

## Cleanup

Drop a worktree's databases before removing it:

```bash
bin/rails db:drop
RAILS_ENV=test bin/rails db:drop
```

## Development

```bash
bundle install
bundle exec rake test
```
