# frozen_string_literal: true

raise "here" if defined?(AgentC::Tools::ReadFile)

module AgentC
  module Tools
    class ReadFile < RubyLLM::Tool
      description "Reads the contents of a file"

      params do
        string(
          :path,
          description: <<~TXT
            Path to file. Must be a child of current directory.

            Only returns 300 lines at a time. Specify line range if possible
            to avoid truncated responses.
          TXT
        )

        number(
          :line_range_start,
          description: "Read lines on or after this line number.",
          required: false
        )

        number(
          :line_range_end,
          description: "Read lines on or before this line number.",
          required: false
        )
      end

      attr_reader :working_dir
      def initialize(working_dir: nil, **)
        raise ArgumentError, "working_dir is required" unless working_dir
        @working_dir = working_dir
      end


      def execute(path:, line_range_start: 0, line_range_end: nil, **params)
        if params.any?
          return "The following params were passed but are not allowed: #{params.keys.join(",")}"
        end

        unless Paths.allowed?(working_dir, path)
          return "Path: #{path} not acceptable. Must be a child of directory: #{working_dir}."
        end

        workspace_path = Paths.relative_to_dir(working_dir, path)

        unless File.exist?(workspace_path)
          return "File not found"
        end

        all_lines = File.read(workspace_path).split("\n")
        lines = all_lines[line_range_start..line_range_end]

        total_lines = lines.length
        max_lines = 300

        # Determine the actual line range being returned (1-indexed for display)
        actual_start = line_range_start + 1
        actual_end = line_range_end ? [line_range_end + 1, all_lines.length].min : all_lines.length

        if total_lines > max_lines
          limited_content = format_with_line_numbers(lines[0...max_lines], actual_start)
          limited_end = actual_start + max_lines - 1
          "Returning lines #{actual_start}-#{limited_end}, out of #{total_lines} total lines:\n\n#{limited_content}"
        elsif line_range_start > 0 || line_range_end
          # Line range was specified
          formatted_content = format_with_line_numbers(lines, actual_start)
          "Returning lines #{actual_start}-#{actual_end}, out of #{all_lines.length} total lines:\n\n#{formatted_content}"
        else
          format_with_line_numbers(lines, 1)
        end
      rescue => e
        "File read error: #{e.class}:#{e.message}"
      end

      private

      # Format lines with line numbers
      def format_with_line_numbers(lines, starting_line_num)
        max_line_num = starting_line_num + lines.length - 1
        width = max_line_num.to_s.length
        lines.map.with_index do |line, idx|
          line_num = starting_line_num + idx
          "%#{width}d: %s" % [line_num, line]
        end.join("\n")
      end
    end
  end
end
