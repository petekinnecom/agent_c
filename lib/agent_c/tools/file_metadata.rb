# frozen_string_literal: true

module AgentC
  module Tools
    class FileMetadata < RubyLLM::Tool
      description "Returns metadata of a file, including line-count, mtime"

      params do
        string(
          :path,
          description: "Path to file. Must be a child of current directory."
        )
      end

      attr_reader :workspace_dir
      def initialize(workspace_dir: nil, **)
        raise ArgumentError, "workspace_dir is required" unless workspace_dir
        @workspace_dir = workspace_dir
      end

      def execute(path:, line_range_start: 0, line_range_end: nil, **params)
        if params.any?
          return "The following params were passed but are not allowed: #{params.keys.join(",")}"
        end

        unless Paths.allowed?(workspace_dir, path)
          return "Path: #{path} not acceptable. Must be a child of directory: #{workspace_dir}."
        end

        workspace_path = Paths.relative_to_dir(workspace_dir, path)

        unless File.exist?(workspace_path)
          return "File not found"
        end

        {
          mtime: File.mtime(workspace_path),
          lines: File.foreach(workspace_path).count,
        }
      end
    end
  end
end
