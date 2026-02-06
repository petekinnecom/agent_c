# frozen_string_literal: true

require "shellwords"

module AgentC
  module Utils
    # Git utility class for managing Git operations in worktrees
    class Git
      attr_reader :dir

      def initialize(dir)
        @dir = dir
      end

      def create_worktree(worktree_dir:, branch:, revision:)
        # Prune any stale worktrees first
        shell.run!("cd #{dir} && git worktree prune")

        # Remove worktree at dir if it exists (don't fail if it doesn't exist)
        shell.run!("cd #{dir} && (git worktree remove #{Shellwords.escape(worktree_dir)} --force 2>/dev/null || true)")

        shell.run!(
          <<~TXT
            cd #{dir} && \
              git worktree add \
                -B #{Shellwords.escape(branch)} \
                #{Shellwords.escape(worktree_dir)} \
                #{Shellwords.escape(revision)}
          TXT
        )
      end

      def diff
        # --intent-to-add will ensure untracked files are included
        # in the diff.
        shell.run!(
          <<~TXT
            cd #{dir} && \
            git add --all --intent-to-add && \
            git diff --relative
          TXT
        )
      end

      def last_revision
        shell.run!("cd #{dir} && git rev-parse @").strip
      end

      def commit_all(message)
        shell.run!("cd #{dir} && git add --all && git commit --no-gpg-sign -m #{Shellwords.escape(message)}")
        last_revision
      end

      def fixup_commit(revision)
        shell.run!("cd #{dir} && git add --all && git commit --no-gpg-sign --fixup #{revision}")
        last_revision
      end

      def reset_hard_all
        shell.run!("cd #{dir} && git add --all && git reset --hard")
      end

      def status
        shell.run!("cd #{dir} && git status")
      end

      def clean?
        !uncommitted_changes?
      end

      def uncommitted_changes?
        # Check for any changes including untracked files
        # Returns true if there are uncommitted changes (staged, unstaged, or untracked)
        status = shell.run!("cd #{dir} && git status --porcelain")
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
