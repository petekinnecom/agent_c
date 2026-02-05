# frozen_string_literal: true

require "ostruct"
require "json-schema"
require "tmpdir"

module AgentC
  module TestHelpers
    # Helper to create a test session with minimal required parameters
    def test_session(
      agent_db_path: File.join(Dir.mktmpdir, "db.sqlite"),
      **overrides
    )
      Session.new(
        agent_db_path:,
        project: "test_project",
        **overrides
      )
    end

    # DummyChat that maps input_text => output_text for testing
    # Use this with Session.new() by passing it as a chat_provider or record parameter
    class DummyChat
      attr_reader :id, :messages_history, :tools_received, :prompts_received, :invocations

      def initialize(
        responses: {},
        prompts: [],
        tools: [],
        cached_prompts: [],
        workspace_dir: nil,
        record: nil,
        session: nil,
        **_options
      )
        @responses = responses
        @id = "test-chat-#{rand(1000)}"
        @messages_history = []
        @prompts_received = prompts
        @tools_received = tools
        @on_end_message_blocks = []
      end

      def ask(input_text)
        # Try to find a matching response
        _, output = (
          @responses.find do |key, value|
            (key.is_a?(Regexp) && input_text.match?(key)) ||
              (key.is_a?(Proc) && key.call(input_text)) ||
              (key == input_text)
          end
        )

        output_text = (
          if output.respond_to?(:call)
            output.call
          else
            output
          end
        )

        raise "No response configured for: #{input_text.inspect}" if output_text.nil?

        # Create a mock message with the input
        user_message = OpenStruct.new(
          role: :user,
          content: input_text,
          to_llm: OpenStruct.new(to_h: { role: :user, content: input_text })
        )

        # Create a mock response message
        response_message = OpenStruct.new(
          role: :assistant,
          content: output_text,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: output_text })
        )

        @messages_history << user_message
        @messages_history << response_message

        # Call all on_end_message hooks
        @on_end_message_blocks.each { |block| block.call(response_message) }

        response_message
      end

      def get(input_text, schema: nil, **options)
        # Similar to ask, but returns parsed JSON as a Hash for structured responses
        response_message = ask(input_text)

        json_schema = schema&.to_json_schema&.fetch(:schema)

        # Parse the response content as JSON
        begin
          result = JSON.parse(response_message.content)
          if json_schema.nil? || JSON::Validator.validate(json_schema, result)
            result
          else
            raise "Failed to get valid response"
          end
        rescue JSON::ParserError
          # If not valid JSON, wrap in a hash
          { "result" => response_message.content }
        end
      end

      def messages(...)
        @messages_history
      end

      def with_tools(*tools)
        @tools_received = tools.flatten
        self
      end

      def on_new_message(&block)
        self
      end

      def on_end_message(&block)
        @on_end_message_blocks << block
        self
      end

      def on_tool_call(&block)
        self
      end

      def on_tool_result(&block)
        self
      end
    end

    # DummyGit for testing git operations without actual git commands
    # Use this by passing it as the git parameter to Pipeline.call
    class DummyGit
      attr_reader :invocations

      def initialize(workspace_dir)
        @workspace_dir = workspace_dir
        @invocations = []
      end

      def uncommitted_changes?
        @has_changes ||= false
      end

      def commit_all(message)
        @invocations << {
          method: :commit_all,
          args: [message],
          params: {}
        }
      end

      def simulate_file_created!
        @has_changes = true
      end

      def method_missing(method, *args, **params)
        @invocations << {
          method:,
          args:,
          params:,
        }
      end

      def respond_to_missing?(method, include_private = false)
        true
      end
    end
  end
end
