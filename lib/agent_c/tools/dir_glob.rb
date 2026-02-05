# frozen_string_literal: true

module AgentC
  module Tools
    class DirGlob < RubyLLM::Tool
      description("Find files in a directory using a ruby-compatible glob pattern.")

      params do
        string(
          :glob_pattern,
          description: "Only returns children paths of the current directory"
        )
      end

      attr_reader :workspace_dir
      def initialize(workspace_dir: nil, **)
        raise ArgumentError, "workspace_dir is required" unless workspace_dir
        @workspace_dir = workspace_dir
      end

      def execute(glob_pattern:, **params)
        if params.any?
          return "The following params were passed but are not allowed: #{params.keys.join(",")}"
        end

        unless Paths.allowed?(workspace_dir, glob_pattern)
          return "Path: #{glob_pattern} not acceptable. Must be a child of directory: #{workspace_dir}."
        end

        results = (
          Dir
            .glob(File.join(workspace_dir, glob_pattern))
            .select { Paths.allowed?(workspace_dir, _1) }
        )

        warning = (
          if results.count > 30
            "Returning 30 of #{results.count} results"
          end
        )

        [warning, results.take(30).to_json].compact.join("\n")
      end
    end
  end
end
