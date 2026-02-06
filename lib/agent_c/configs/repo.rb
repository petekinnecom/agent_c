# frozen_string_literal: true

module AgentC
  module Configs
    class Repo
      attr_reader(
        :dir,
        :initial_revision,
        :working_subdir,
        :worktrees_root_dir,
        :worktree_branch_prefix,
        :worktree_envs,
        :logger,
      )
      def initialize(
        dir:,
        initial_revision:,
        working_subdir: "",
        worktrees_root_dir:,
        worktree_branch_prefix:,
        worktree_envs:,
        logger:
      )
        @dir = dir
        @initial_revision = initial_revision
        @working_subdir = working_subdir
        @worktrees_root_dir = worktrees_root_dir
        @worktree_branch_prefix = worktree_branch_prefix
        @worktree_envs = worktree_envs
        @logger = logger
      end

      def workspaces(store)
        git = Utils::Git.new(dir)
        logger.info("Checking worktrees")

        worktree_configs.map { |spec|
          worktree_dir = spec.fetch(:dir)

          if store.workspace.where(dir: spec.fetch(:workspace_dir)).exists?
            logger.info("worktree record exists at #{worktree_dir}, not creating/resetting worktree")
          else
            logger.info("creating/resetting worktree at: #{worktree_dir}")
            git.create_worktree(
              worktree_dir: worktree_dir,
              branch: spec.fetch(:branch),
              revision: initial_revision,
            )
          end

          store
            .workspace
            .ensure_created!(
              dir: spec.fetch(:workspace_dir),
              env: spec.fetch(:env)
            )
        }.tap { logger.info("done checking worktrees")}
      end

      private

      def create_worktrees(store)
      end

      def workspace_configs
        worktree_configs.map { _1.slice(:env, :dir) }
      end

      private

      def worktree_configs
        @envs_with_paths ||= (
          worktree_envs
            .each_with_index
            .map { |env, i|
              branch = "#{worktree_branch_prefix}-#{i}"
              dir = File.join(worktrees_root_dir, branch)

              {
                env:,
                dir: ,
                branch:,
                workspace_dir: File.join(dir, working_subdir)
              }
            }
        )
      end
    end
  end
end
