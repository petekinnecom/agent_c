# frozen_string_literal: true

require "open3"

module AgentC
  module Tools
    class GitStatus < RubyLLM::Tool
      description <<~DESC
        Return the current git status
      DESC

      params do
      end

      attr_reader :workspace_dir
      def initialize(workspace_dir: nil, **)
        raise ArgumentError, "workspace_dir is required" unless workspace_dir
        @workspace_dir = workspace_dir
      end

      def execute(**params)
        if params.any?
          return "The following params were passed but are not allowed: #{params.keys.join(",")}"
        end

        Utils::Git.new(workspace_dir).status
      end
    end
  end
end
