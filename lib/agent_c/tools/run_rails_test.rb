# frozen_string_literal: true

require "shellwords"

module AgentC
  module Tools
    class RunRailsTest < RubyLLM::Tool
      description "Runs a minitest rails test using bin/rails test {path} --name={name_of_test_method}"

      params do
        string(
          :path,
          description: "Path to file. Must be a child of current directory.",
          required: true
        )
        string(
          :test_method_name,
          description: "The name of the specific test method to run",
          required: false
        )
        boolean(
          :disable_spring,
          description: <<~TXT,
            Disable spring if the errors are weird and you want to make sure
            it's not a spring issue. Prefer to use spring unless you are
            encountering weird behavior.
          TXT
          required: false
        )
      end

      attr_reader :working_dir, :env
      def initialize(
        working_dir: nil,
        env: {},
        **
      )
        raise ArgumentError, "working_dir is required" unless working_dir
        @env = env
        @working_dir = working_dir
      end

      def execute(path:, test_method_name: nil, disable_spring: false, **params)

        # Spring hangs, need to timeout unresponsive shells
        disable_spring = true

        if params.any?
          return "The following params were passed but are not allowed: #{params.keys.join(",")}"
        end

        unless Paths.allowed?(working_dir, path)
          return "Path: #{path} not acceptable. Must be a child of directory: #{working_dir}."
        end

        workspace_path = Paths.relative_to_dir(working_dir, path)

        env_string = env.is_a?(Hash) ? env.map { |k, v| "#{k}=#{Shellwords.escape(v)}"}.join(" ") : env

        env_string += " DISABLE_SPRING=1" if disable_spring

        cmd = <<~TXT.chomp
          cd #{working_dir} && \
          #{env_string} bundle exec rails test #{path} #{test_method_name && "--name='#{test_method_name}'"}
        TXT

        lines = []
        result = nil
        Bundler.with_unbundled_env do
          result = shell.run(cmd) do |stream, line|
            lines << "[#{stream}] #{line}"
          end
        end

        return <<~TXT
          Command exited #{result.success? ? "successfully" : "with non-zero exit code"}
          ---
          #{lines.join("\n")}
        TXT
      end

      def shell
        AgentC::Utils::Shell
      end
    end
  end
end
