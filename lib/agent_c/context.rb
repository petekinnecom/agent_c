# frozen_string_literal: true

module AgentC
  class Context
    attr_reader :config
    def initialize(store:, session:, repo: nil, workspace: nil)
      raise ArgumentError.new("must pass workspace or repo") unless workspace || repo

      @store_config = store
      @session_config = session
      @workspace_config = workspace
      @repo_config = repo
    end

    def store
      @store ||= (
        if @store_config.is_a?(Hash)
          @store_config.fetch(:class).new(**@store_config.fetch(:config))
        else
          @store_config
        end
      )
    end

    def workspace
      raise "Multiple workspaces configured" unless workspaces.count == 1

      workspaces.first
    end

    def workspaces
      @workspaces ||= (
        if @workspace_config.is_a?(Hash)
          [store.workspace.ensure_created!(**@workspace_config)]
        elsif @repo_config
          # Note: This method provision the worktrees if they don't exist
          Configs::Repo.new(logger: session.logger, **@repo_config).workspaces(store)
        elsif @workspace_config.is_a?(Array)
          @workspace_config
        else
          [@workspace_config]
        end
      )
    end

    def session
      @session ||= (
        if @session_config.is_a?(Hash)
          Session.new(**@session_config)
        else
          @session_config
        end
      )
    end
  end
end
