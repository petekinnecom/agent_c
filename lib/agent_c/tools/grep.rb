# frozen_string_literal: true

require "open3"

module AgentC
  module Tools
    class Grep < RubyLLM::Tool
      description <<~DESC
        Searches for patterns in files using git grep. Returns matching lines
        with file paths and line numbers.
      DESC

      params do
        string(
          :pattern,
          description: <<~DESC,
            The regex pattern to search for. Use standard regex syntax.
          DESC
          required: true
        )
        string(
          :file_pattern,
          description: <<~DESC,
            Optional glob pattern to limit search to specific files
            (e.g., '*.rb', 'app/**/*.js'). If omitted, searches all files.
          DESC
          required: false
        )
        boolean(
          :ignore_case,
          description: <<~DESC,
            If true, performs case-insensitive search. Default is false.
          DESC
          required: false
        )
        integer(
          :context_lines,
          description: <<~DESC,
            Number of context lines to show before and after each match.
            Default is 0.
          DESC
          required: false
        )
        integer(
          :line_range_start,
          description: <<~DESC,
            Return results starting from this line number (1-indexed).
            Default is 1.
          DESC
          required: false
        )
        integer(
          :line_range_end,
          description: <<~DESC,
            Return results up to and including this line number (1-indexed).
            If omitted, returns to the end.
          DESC
          required: false
        )
      end

      attr_reader :workspace_dir
      def initialize(workspace_dir: nil, **)
        raise ArgumentError, "workspace_dir is required" unless workspace_dir
        @workspace_dir = workspace_dir
      end

      def execute(pattern:, file_pattern: nil, ignore_case: false, context_lines: 0, line_range_start: 1, line_range_end: nil, **params)
        if params.any?
          return "The following params were passed but are not allowed: #{params.keys.join(",")}"
        end

        Dir.chdir(workspace_dir) do

          cmd = ["git", "grep", "-n", "--extended-regexp"]  # -n shows line numbers

          cmd << "-i" if ignore_case
          cmd << "-C" << context_lines.to_s if context_lines > 0

          cmd << "-e" << pattern

          if file_pattern
            cmd << "--" << file_pattern
          end


          stdout, stderr, status = Open3.capture3(*cmd)

          if status.success?
            lines = stdout.force_encoding("UTF-8").split("\n")

            # Apply line range (convert to 0-indexed)
            start_idx = [line_range_start - 1, 0].max
            end_idx = line_range_end ? line_range_end - 1 : -1
            lines = lines[start_idx..end_idx] || []

            lines = lines.map { |l| l[0..100]}

            total_lines = lines.length
            max_lines = 300

            if total_lines > max_lines
              limited_content = lines[0...max_lines].join("\n")
              return "Returning #{max_lines} lines out of #{total_lines} total lines:\n\n#{limited_content}"
            else
              return lines.join("\n")
            end
          elsif status.exitstatus == 1
            # Exit status 1 means no matches found
            return "No matches found."
          else
            # Other error
            return "Error: #{stderr}"
          end
        end
      end
    end
  end
end
