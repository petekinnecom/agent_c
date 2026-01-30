# frozen_string_literal: true

module AgentC
  module Tools
    class EditFile < RubyLLM::Tool
      description "Edits a file with various operations: overwrite entire file, replace specific lines, insert at position, or append"

      params do
        string(
          :path,
          description: "Path to file. Must be a child of current directory.",
          required: true
        )
        string(
          :mode,
          description: "Operation mode: 'overwrite' (replace entire file), 'replace_lines' (replace line range), 'insert_at_line' (insert before specified line), 'append' (add to end)",
          enum: ["overwrite", "replace_lines", "insert_at_line", "append"],
          required: true
        )
        string(
          :content,
          description: "The content to write, insert, or append. Can be multi-line.",
          required: true
        )
        integer(
          :start_line,
          description: <<~TXT,
            For replace_lines: first line to replace, inclusive (1-indexed).
            For insert_at_line: line before which to insert (1=start of file, 999999=end of file).
          TXT
          required: false
        )
        integer(
          :end_line,
          description: "For replace_lines only: last line to replace, inclusive (1-indexed).",
          required: false
        )
      end

      attr_reader :working_dir
      def initialize(working_dir: nil, **)
        raise ArgumentError, "working_dir is required" unless working_dir
        @working_dir = working_dir
      end

      def execute(path:, mode:, content:, start_line: nil, end_line: nil, **params)
        if params.any?
          return "The following params were passed but are not allowed: #{params.keys.join(",")}"
        end

        unless Paths.allowed?(working_dir, path)
          return "Path: #{path} not acceptable. Must be a child of directory: #{working_dir}."
        end

        workspace_path = Paths.relative_to_dir(working_dir, path)

        case mode
        when "overwrite"
          FileUtils.mkdir_p(File.dirname(workspace_path))
          File.write(workspace_path, content)

        when "replace_lines"
          return "start_line and end_line required for replace_lines mode" unless start_line && end_line
          return "start_line must be <= end_line" if start_line > end_line

          lines = File.exist?(workspace_path) ? File.readlines(workspace_path, chomp: true) : []

          # Convert to 0-indexed
          start_idx = start_line - 1
          end_idx = end_line - 1

          # Replace the range with new content lines
          new_lines = content.split("\n")
          lines[start_idx..end_idx] = new_lines

          File.write(workspace_path, lines.join("\n") + "\n")

        when "insert_at_line"
          return "start_line required for insert_at_line mode" unless start_line

          lines = File.exist?(workspace_path) ? File.readlines(workspace_path, chomp: true) : []

          # Insert before the specified line (1-indexed)
          insert_idx = start_line - 1
          insert_idx = [0, [insert_idx, lines.length].min].max  # Clamp to valid range

          new_lines = content.split("\n")
          lines.insert(insert_idx, *new_lines)

          File.write(workspace_path, lines.join("\n") + "\n")

        when "append"
          FileUtils.mkdir_p(File.dirname(workspace_path))
          File.open(workspace_path, "a") do |f|
            f.write(content)
            f.write("\n") unless content.end_with?("\n")
          end
        end

        # Run syntax check for Ruby files
        if workspace_path.end_with?(".rb")
          syntax_check = `ruby -c #{workspace_path} 2>&1`
          unless $?.success?
            return "File successfully edited, but syntax errors were found:\n#{syntax_check}"
          end
        end

        true
      end
    end
  end
end
