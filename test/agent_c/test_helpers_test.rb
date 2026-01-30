# frozen_string_literal: true

require "test_helper"

module AgentC
  class TestHelpersTest < Minitest::Test
    include TestHelpers

    def test_dummy_chat_with_prompt_success_response
      session = test_session(
        chat_provider: ->(**params) {
          DummyChat.new(
            responses: {
              "What is 2+2?" => '{"status": "success", "answer": "4"}'
            },
            **params
          )
        }
      )

      result = session.prompt(
        prompt: "What is 2+2?",
        schema: -> { string(:answer) }
      )

      assert result.success?
      assert_equal "4", result.data["answer"]
    end

    def test_dummy_chat_with_prompt_error_response
      session = test_session(
        chat_provider: ->(**params) {
          DummyChat.new(
            responses: {
              "What is impossible?" => '{"status": "error", "message": "Cannot compute"}'
            },
            **params
          )
        }
      )

      result = session.prompt(
        prompt: "What is impossible?",
        schema: -> { string(:result) }
      )

      refute result.success?
      assert_equal "Cannot compute", result.error_message
    end

    def test_dummy_chat_with_prompt_regex_matcher
      session = test_session(
        chat_provider: ->(**params) {
          DummyChat.new(
            responses: {
              /extract.*email/ => '{"status": "success", "email": "test@example.com"}'
            },
            **params
          )
        }
      )

      result = session.prompt(
        prompt: "Please extract the email from this text",
        schema: -> { string(:email) }
      )

      assert result.success?
      assert_equal "test@example.com", result.data["email"]
    end

    def test_dummy_chat_with_prompt_proc_matcher
      session = test_session(
        chat_provider: ->(**params) {
          DummyChat.new(
            responses: {
              ->(text) { text.include?("hello") } => '{"status": "success", "greeting": "Hi there!"}'
            },
            **params
          )
        }
      )

      result = session.prompt(
        prompt: "Say hello to me",
        schema: -> { string(:greeting) }
      )

      assert result.success?
      assert_equal "Hi there!", result.data["greeting"]
    end

    def test_dummy_chat_with_prompt_no_match
      session = test_session(
        chat_provider: ->(**params) {
          DummyChat.new(
            responses: {
              "specific question" => '{"status": "success", "answer": "yes"}'
            },
            **params
          )
        }
      )

      result = session.prompt(
        prompt: "different question",
        schema: -> { string(:answer) }
      )

      refute result.success?
      assert_match(/No response configured/, result.error_message)
    end

    def test_dummy_chat_returns_chat_interface
      session = test_session
      dummy_chat = DummyChat.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = session.chat(tools: [], record: dummy_chat)

      assert_respond_to chat, :ask
      assert_respond_to chat, :get
    end

    def test_dummy_chat_ask_method
      session = test_session
      dummy_chat = DummyChat.new(responses: {
        "Hello" => "Hi there!"
      })

      chat = session.chat(tools: [], record: dummy_chat)
      response = chat.ask("Hello")

      assert_equal "Hi there!", response.content
    end

    def test_dummy_chat_get_method
      session = test_session
      dummy_chat = DummyChat.new(responses: {
        /Get data/ => '{"status": "success", "value": "test"}'
      })

      chat = session.chat(tools: [], record: dummy_chat)
      result = chat.get("Get data", schema: nil)

      assert_equal "success", result["status"]
      assert_equal "test", result["value"]
    end

    def test_dummy_chat_with_prompt_array_prompt
      session = test_session(
        chat_provider: ->(**params) {
          DummyChat.new(
            responses: {
              "Line 1\nLine 2" => '{"status": "success", "result": "combined"}'
            },
            **params
          )
        }
      )

      result = session.prompt(
        prompt: ["Line 1", "Line 2"],
        schema: -> { string(:result) }
      )

      assert result.success?
      assert_equal "combined", result.data["result"]
    end

    def test_dummy_chat_with_callable_response_for_side_effects
      # Create a temp file path for testing
      temp_file = File.join(Dir.tmpdir, "dummy_chat_test_#{rand(10000)}.txt")

      # Callable response can perform side effects like writing to a file
      session = test_session(
        chat_provider: ->(**params) {
          DummyChat.new(
            responses: {
              "Write hello to file" => -> {
                File.write(temp_file, "Hello from DummyChat!")
                '{"status": "success", "message": "File written"}'
              }
            },
            **params
          )
        }
      )

      # Ensure file doesn't exist before test
      File.delete(temp_file) if File.exist?(temp_file)
      refute File.exist?(temp_file)

      # Make the request - the callable will be invoked
      result = session.prompt(
        prompt: "Write hello to file",
        schema: -> { string(:message) }
      )

      # Verify the response
      assert result.success?
      assert_equal "File written", result.data["message"]

      # Verify the side effect occurred
      assert File.exist?(temp_file)
      assert_equal "Hello from DummyChat!", File.read(temp_file)

      # Cleanup
      File.delete(temp_file) if File.exist?(temp_file)
    end

    def test_dummy_chat_callable_response_with_chat_ask
      call_count = 0

      session = test_session
      dummy_chat = DummyChat.new(responses: {
        "Count calls" => -> {
          call_count += 1
          "Called #{call_count} time(s)"
        }
      })

      chat = session.chat(tools: [], record: dummy_chat)

      # First call
      response1 = chat.ask("Count calls")
      assert_equal "Called 1 time(s)", response1.content

      # Second call - demonstrates the callable is invoked each time
      response2 = chat.ask("Count calls")
      assert_equal "Called 2 time(s)", response2.content

      assert_equal 2, call_count
    end
  end
end
