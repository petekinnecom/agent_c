# frozen_string_literal: true

require "test_helper"
require "ruby_llm"
require "ostruct"

module AgentC
  module Agent
    class ChatTest < Minitest::Test
    include TestHelpers

    def setup
      @session = Session.new(
        agent_db_path: DB_PATH,
        project: "test",
        run_id: "test-run",
        workspace_dir: "/tmp/test",
        logger: Logger.new(nil)
      )
    end

    def test_ask_returns_configured_response
      record = DummyChat.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = @session.chat(record: record, tools: [])
      response = chat.ask("Hello")

      assert_equal "Hi there!", response.content
    end

    def test_ask_with_multiple_responses
      record = DummyChat.new(responses: {
        "What is 2+2?" => "4",
        "What is the capital of France?" => "Paris"
      })

      chat = @session.chat(record: record, tools: [])

      response1 = chat.ask("What is 2+2?")
      assert_equal "4", response1.content

      response2 = chat.ask("What is the capital of France?")
      assert_equal "Paris", response2.content
    end

    def test_ask_raises_for_unknown_input
      record = DummyChat.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = @session.chat(record: record, tools: [])

      error = assert_raises(RuntimeError) do
        chat.ask("Unknown input")
      end

      assert_match(/No response configured for/, error.message)
    end

    def test_id_returns_record_id
      record = DummyChat.new(responses: {})
      chat = @session.chat(record: record, tools: [])

      assert_equal record.id, chat.id
    end

    def test_to_h_returns_message_history
      record = DummyChat.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = @session.chat(record: record, tools: [])
      chat.ask("Hello")

      history = chat.to_h

      assert_equal 2, history.length
      assert_equal :user, history[0][:role]
      assert_equal "Hello", history[0][:content]
      assert_equal :assistant, history[1][:role]
      assert_equal "Hi there!", history[1][:content]
    end

    def test_get_with_valid_json_schema
      record = DummyChat.new(responses: {
        ->(text) { text.include?("Get person data") } => '{"name": "Alice", "age": 30}'
      })

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:name, description: "Person's name")
        integer(:age, description: "Person's age")
      end

      result = chat.get("Get person data", schema: schema)

      assert_equal "Alice", result["name"]
      assert_equal 30, result["age"]
    end

    def test_get_with_confirmation
      # Test that get waits for confirmed answer
      call_count = 0
      record = DummyChat.new(responses: {})

      # Override ask to return different answers
      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        answer = call_count == 1 ? '{"value": "A"}' : '{"value": "A"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:value, description: "A value")
      end

      result = chat.get("Get value", schema: schema, confirm: 2, out_of: 2)

      assert_equal "A", result["value"]
      assert_equal 2, call_count
    end

    def test_refine_makes_multiple_attempts
      call_count = 0
      record = DummyChat.new(responses: {})

      # Override ask to track refinement
      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        answer = '{"result": "refined answer"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:result, description: "The result")
      end

      result = chat.refine("Give me an answer", schema: schema, times: 2)

      assert_equal "refined answer", result["result"]
      assert_equal 2, call_count
    end

    def test_messages_returns_message_history
      record = DummyChat.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = @session.chat(record: record, tools: [])
      chat.ask("Hello")

      messages = chat.messages

      assert_equal 2, messages.length
      assert_equal "Hello", messages[0].content
      assert_equal "Hi there!", messages[1].content
    end

    def test_chat_with_custom_tools
      record = DummyChat.new(responses: {
        "Test" => "Response"
      })

      custom_tools = [Tools::ReadFile.new(workspace_dir: "/tmp")]
      chat = @session.chat(record: record, tools: custom_tools)

      assert_equal 1, chat.tools.length
      assert_instance_of Tools::ReadFile, chat.tools.first
    end

    def test_chat_with_custom_prompts
      record = DummyChat.new(responses: {
        "Test" => "Response"
      })

      cached_prompts = ["You are a helpful assistant"]
      chat = @session.chat(record: record, cached_prompts: cached_prompts, tools: [])

      assert_equal cached_prompts, chat.cached_prompts
    end

    def test_get_with_invalid_json_then_valid
      # Test retry logic when first response is invalid JSON
      call_count = 0
      record = DummyChat.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # First call returns invalid JSON, second returns valid
        answer = call_count == 1 ? 'invalid json' : '{"data": "valid"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      result = chat.get("Get data", schema: schema)

      assert_equal "valid", result["data"]
      assert_equal 2, call_count
    end

    def test_get_with_schema_violation_then_valid
      # Test retry logic when first response doesn't match schema
      call_count = 0
      record = DummyChat.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # First call returns JSON that doesn't match schema, second returns valid
        answer = call_count == 1 ? '{}' : '{"data": "valid"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      result = chat.get("Get data", schema: schema)

      assert_equal "valid", result["data"]
      assert_equal 2, call_count
    end

    def test_get_with_error_response
      # Test error response from schema
      record = DummyChat.new(responses: {
        ->(text) { text.include?("impossible task") } => '{"unable_to_fulfill_request_error": "Cannot complete this task"}'
      })

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      result = chat.get("Do an impossible task", schema: schema)

      assert_equal "Cannot complete this task", result["unable_to_fulfill_request_error"]
    end

    def test_refine_with_second_refinement_different
      # Test that refine includes prior answer in subsequent requests
      call_count = 0
      prior_answer_found = false
      record = DummyChat.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1

        # Second request should include the prior answer
        if call_count == 2
          expected_prompt = I18n.t(
            "agent.chat.refine.system_message",
            prior_answer: '{"result": "first answer"}',
            original_message: "Give me an answer"
          )
          prior_answer_found = input_text.include?("BEGIN-PRIOR-ANSWER") && input_text.include?("first answer")
        end

        answer = call_count == 1 ? '{"result": "first answer"}' : '{"result": "refined answer"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:result, description: "The result")
      end

      result = chat.refine("Give me an answer", schema: schema, times: 2)

      assert_equal "refined answer", result["result"]
      assert_equal 2, call_count
      assert prior_answer_found, "Second refinement should include prior answer"
    end

    def test_get_with_no_confirmation_reached
      # Test that get raises when confirmation threshold not met
      call_count = 0
      record = DummyChat.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # Each call returns a different answer
        answer = '{"value": "' + "answer#{call_count}" + '"}'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:value, description: "A value")
      end

      error = assert_raises(RuntimeError) do
        chat.get("Get value", schema: schema, confirm: 2, out_of: 3)
      end

      assert_match(/Unable to confirm an answer/, error.message)
      assert_equal 3, call_count
    end

    def test_get_with_nil_schema
      # Test that get works without a schema
      record = DummyChat.new(responses: {
        ->(text) { text.include?("Get unstructured data") } => '{"result": "some data"}'
      })

      chat = @session.chat(record: record, tools: [])

      result = chat.get("Get unstructured data", schema: nil)

      assert_equal "some data", result["result"]
    end

    def test_get_result_max_retries_exceeded
      # Test that get_result raises after 5 failed attempts
      call_count = 0
      record = DummyChat.new(responses: {})

      record.define_singleton_method(:ask) do |input_text|
        call_count += 1
        # Always return invalid JSON
        answer = 'this is not valid json at all'

        response_message = OpenStruct.new(
          role: :assistant,
          content: answer,
          to_llm: OpenStruct.new(to_h: { role: :assistant, content: answer })
        )

        @messages_history << response_message
        response_message
      end

      chat = @session.chat(record: record, tools: [])

      schema = Schema.result do
        string(:data, description: "Some data")
      end

      error = assert_raises(RuntimeError) do
        chat.get("Get data", schema: schema)
      end

      assert_match(/Failed to get valid response/, error.message)
      assert_equal 5, call_count
    end

    def test_to_h_with_tool_calls
      # Test that to_h properly handles messages with tool_calls
      record = DummyChat.new(responses: {})

      # Create a mock message with tool_calls
      tool_call = OpenStruct.new(to_h: { name: "test_tool", arguments: { arg: "value" } })
      tool_calls_hash = { "call_1" => tool_call }

      message_with_tools = OpenStruct.new(
        role: :assistant,
        content: "Using tools",
        to_llm: OpenStruct.new(
          to_h: {
            role: :assistant,
            content: "Using tools",
            tool_calls: tool_calls_hash
          }
        )
      )

      record.instance_variable_set(:@messages_history, [message_with_tools])

      chat = @session.chat(record: record, tools: [])

      history = chat.to_h

      assert_equal 1, history.length
      assert_equal :assistant, history[0][:role]
      assert history[0].key?(:tool_calls)
      assert_equal 1, history[0][:tool_calls].length
      assert_equal "test_tool", history[0][:tool_calls][0][:name]
    end

    def test_normalize_schema_with_any_one_of
      # Test that AnyOneOf schema from Schema.result works correctly
      record = DummyChat.new(responses: {
        ->(text) { text.include?("Get data") } => '{"value": "test"}'
      })

      chat = @session.chat(record: record, tools: [])

      # Schema.result already returns an AnyOneOf
      schema = Schema.result do
        string(:value, description: "A value")
      end

      assert_instance_of Schema::AnyOneOf, schema

      result = chat.get("Get data", schema: schema)

      assert_equal "test", result["value"]
    end

    def test_prompt_returns_success_response
      schema_proc = -> {
        string(:confirmation_test_path, description: "The path to the test file.")
      }

      record = TestHelpers::DummyChat.new(responses: {
        ->(text) { text.include?("Find test path") } => '{"confirmation_test_path": "/path/to/test.rb"}'
      })

      # Monkey-patch session to use DummyChat
      @session.define_singleton_method(:chat) do |**params|
        Agent::Chat.new(record: record, **params.merge(session: self))
      end

      response = @session.prompt(
        tool_args: { workspace_dir: "/tmp/workspace", env: { "FOO" => "bar" } },
        tools: [:read_file, :edit_file],
        cached_prompt: ["You are a helpful assistant"],
        prompt: ["Find test path"],
        schema: schema_proc
      )

      assert response.success?
      assert_equal "success", response.status
      assert_equal "/path/to/test.rb", response.data["confirmation_test_path"]
      refute_includes response.data.keys, "status"
      assert_match(/test-chat-\d+/, response.chat_id)
    end

    def test_prompt_returns_error_response_from_exception
      schema_proc = -> {
        string(:confirmation_test_path, description: "The path to the test file.")
      }

      record = TestHelpers::DummyChat.new(responses: {})
      record.define_singleton_method(:ask) do |_|
        raise "Something went wrong"
      end

      # Monkey-patch session to use DummyChat
      @session.define_singleton_method(:chat) do |**params|
        Agent::Chat.new(record: record, **params.merge(session: self))
      end

      response = @session.prompt(
        tool_args: { workspace_dir: "/tmp/workspace" },
        tools: [:read_file],
        cached_prompt: [],
        prompt: ["Find test path"],
        schema: schema_proc
      )

      refute response.success?
      assert_equal "error", response.status
      assert_match(/RuntimeError:Something went wrong/, response.error_message)
      assert_match(/test-chat-\d+/, response.chat_id)
    end

    def test_prompt_returns_error_response_from_llm
      schema_proc = -> {
        string(:result, description: "The result")
      }

      record = TestHelpers::DummyChat.new(responses: {
        ->(text) { text.include?("impossible task") } => '{"unable_to_fulfill_request_error": "I cannot complete this task"}'
      })

      # Monkey-patch session to use DummyChat
      @session.define_singleton_method(:chat) do |**params|
        Agent::Chat.new(record: record, **params.merge(session: self))
      end

      response = @session.prompt(
        tool_args: { workspace_dir: "/tmp" },
        tools: [],
        cached_prompt: [],
        prompt: ["Do an impossible task"],
        schema: schema_proc
      )

      refute response.success?
      assert_equal "error", response.status
      assert_equal "I cannot complete this task", response.error_message
      assert_match(/test-chat-\d+/, response.chat_id)
    end

    def test_prompt_data_raises_on_error_response
      response = Agent::ChatResponse.new(
        chat_id: "test-123",
        raw_response: {"unable_to_fulfill_request_error" => "Something went wrong"}
      )

      refute response.success?
      assert_equal "error", response.status

      error = assert_raises(RuntimeError) do
        response.data
      end

      assert_match(/Cannot call data on failed response/, error.message)
    end

    def test_prompt_error_message_raises_on_success_response
      response = Agent::ChatResponse.new(
        chat_id: "test-123",
        raw_response: {"confirmation_test_path" => "/path/to/test.rb"}
      )

      assert response.success?
      assert_equal "success", response.status

      error = assert_raises(RuntimeError) do
        response.error_message
      end

      assert_match(/Cannot call error_message on successful response/, error.message)
    end

    def test_prompt_with_array_prompt
      schema_proc = -> {
        string(:result, description: "The result")
      }

      record = TestHelpers::DummyChat.new(responses: {})
      record.define_singleton_method(:ask) do |input_text|
        # Verify that array prompts are joined with newlines
        if input_text.include?("First line\nSecond line")
          response_message = OpenStruct.new(
            role: :assistant,
            content: '{"result": "success"}',
            to_llm: OpenStruct.new(to_h: { role: :assistant, content: '{"result": "success"}' })
          )
          @messages_history << response_message
          response_message
        else
          raise "Unexpected prompt format: #{input_text}"
        end
      end

      # Monkey-patch session to use DummyChat
      @session.define_singleton_method(:chat) do |**params|
        Agent::Chat.new(record: record, **params.merge(session: self))
      end

      response = @session.prompt(
        tool_args: { workspace_dir: "/tmp" },
        tools: [],
        cached_prompt: [],
        prompt: ["First line", "Second line"],
        schema: schema_proc
      )

      assert response.success?
      assert_equal "success", response.status
      assert_equal "success", response.data["result"]
      end
    end
  end
end
