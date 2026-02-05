# frozen_string_literal: true

module AgentC
  module Tools
    NAMES = {
      read_file: ReadFile,
      edit_file: EditFile,
      grep: Grep,
      file_metadata: FileMetadata,
      dir_glob: DirGlob,
      run_rails_test: RunRailsTest,
    }

    def self.all(**params)
      NAMES.values.map { _1.new(**params) }
    end

    def self.resolve(value:, available_tools:, args:, workspace_dir:)

      # ensure any args passed have a
      # workspace_dir.
      resolved_args = (
        if args.key?(:workspace_dir)
          args
        else
          args.merge(workspace_dir:)
        end
      )

      # If they passed a tool instance, nothing to do
      if value.is_a?(RubyLLM::Tool)
        return value
      elsif value.is_a?(Symbol) || value.is_a?(String)
        # They passed the tool name
        # we must initialize it with
        # the standard args
        tool_name = value.to_sym
        unless available_tools.key?(tool_name)
          raise ArgumentError, <<~TXT
            Unknown tool name: #{value.inspect}.
            If you wish to use a custom tool you must configure
            it by passing `extra_tools` to the Session.
          TXT
        end

        klass_or_instance = available_tools.fetch(tool_name)

        if klass_or_instance.is_a?(RubyLLM::Tool)
          klass_or_instance
        else
          klass_or_instance.new(**resolved_args)
        end
      elsif value.is_a?(Class) && value.ancestors.include?(RubyLLM::Tool)
        value.new(**resolved_args)
      else
        raise ArgumentError, "unknown tool specified: #{value.inspect}"
      end
    end
  end
end
