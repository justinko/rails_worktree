require_relative "lib/rails_worktree/version"

Gem::Specification.new do |spec|
  spec.name = "rails_worktree"
  spec.version = RailsWorktree::VERSION
  spec.authors = [ "Justin Ko" ]
  spec.summary = "Isolated Rails development in Git worktrees created by Orca, Claude Code, and Codex"
  spec.description = "Per-worktree databases, cookies, and Portless URLs, plus a setup script wired into Orca, Claude Code, and Codex."
  spec.homepage = "https://github.com/justinko/rails_worktree"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "railties", ">= 8.0"
end
