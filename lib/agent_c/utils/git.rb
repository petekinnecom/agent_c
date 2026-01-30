# frozen_string_literal: true

require "shellwords"

module AgentC
  module Utils
    # Git utility class for managing Git operations in worktrees
    class Git
      attr_reader :repo_path

      def initialize(repo_path)
        @repo_path = repo_path
      end

      def create_worktree(dir:, branch:, revision:)
        # Prune any stale worktrees first
        shell.run!("cd #{repo_path} && git worktree prune")

        # Remove worktree at dir if it exists (don't fail if it doesn't exist)
        shell.run!("cd #{repo_path} && (git worktree remove #{Shellwords.escape(dir)} --force 2>/dev/null || true)")

        shell.run!(
          <<~TXT
            cd #{repo_path} && \
              git worktree add \
                -B #{Shellwords.escape(branch)} \
                #{Shellwords.escape(dir)} \
                #{Shellwords.escape(revision)}
          TXT
        )
      end

      def diff
        shell.run!("cd #{repo_path} && git status --porcelain")
      end

      def last_revision
        shell.run!("cd #{repo_path} && git rev-parse @").strip
      end

      def commit_all(message)
        shell.run!("cd #{repo_path} && git add --all && git commit --no-gpg-sign -m #{Shellwords.escape(message)}")
        last_revision
      end

      def fixup_commit(revision)
        shell.run!("cd #{repo_path} && git add --all && git commit --no-gpg-sign --fixup #{revision}")
        last_revision
      end

      def reset_hard_all
        shell.run!("cd #{repo_path} && git add --all && git reset --hard")
      end

      def clean?
        !uncommitted_changes?
      end

      def uncommitted_changes?
        # Check for any changes including untracked files
        # Returns true if there are uncommitted changes (staged, unstaged, or untracked)
        status = shell.run!("cd #{repo_path} && git status --porcelain")
        !status.strip.empty?
      end

      private

      def shell
        AgentC::Utils::Shell
      end
    end

    # TODO: Add more utility classes here as needed
  end
end
