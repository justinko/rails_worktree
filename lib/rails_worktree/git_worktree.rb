require "digest"

module RailsWorktree
  class GitWorktree
    attr_reader :root

    def initialize(root)
      @root = File.realpath(root)
    end

    def linked?
      git_paths.first != git_paths.last
    end

    def identity
      name = File.basename(root).downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_+/, "")[0, 12].sub(/_+\z/, "")
      "#{name.empty? ? "worktree" : name}_#{digest}"
    end

    def service_name(base_name)
      linked? ? "#{identity.tr("_", "-")}.#{base_name}" : base_name
    end

    def link_file(relative_path)
      return false unless linked?

      destination = File.join(root, relative_path)
      return false if File.exist?(destination) || File.symlink?(destination)

      main = git_output("worktree", "list", "--porcelain", "-z").split("\0\0").first.split("\0")
      return false if main.include?("bare")

      source = File.join(main.first.delete_prefix("worktree "), relative_path)
      return false unless File.file?(source)

      File.symlink(source, destination)
      true
    end

    # Absolute path for per-worktree state inside the Git directory, e.g. setup markers.
    def git_path(name)
      git_output("rev-parse", "--path-format=absolute", "--git-path", name).chomp
    end

    private
      def digest
        @digest ||= Digest::SHA256.hexdigest(root)[0, 8]
      end

      def git_paths
        @git_paths ||= if File.exist?(File.join(root, ".git"))
          git_output("rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir").lines.map(&:chomp)
        else
          [ nil, nil ]
        end
      end

      def git_output(*arguments)
        output = IO.popen([ "git", "-C", root, *arguments ], err: File::NULL, &:read)
        raise "Cannot inspect Git worktree at #{root}; check that Git is installed and the checkout is intact" unless $?.success?

        output
      end
  end
end
