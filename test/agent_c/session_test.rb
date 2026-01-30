# frozen_string_literal: true

require "test_helper"
require "ruby_llm"

module AgentC
  class SessionTest < Minitest::Test
    include TestHelpers

    def test_abort_cost_raises_when_project_threshold_exceeded
      # Create session with db_path and abort cost threshold
      session = Session.new(
        project: "abort_test_project",
        run_id: "abort_test_run",
        agent_db_path: DB_PATH,
        logger: Logger.new(nil),
        max_spend_project: 1.0,
        ruby_llm: {
          bedrock_api_key: "test-key",
          bedrock_secret_key: "test-secret",
          bedrock_region: "us-west-2",
          default_model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        }
      )

      # Create expensive messages
      model = session.agent_store.model.find_or_create_by!(
        model_id: "test-model",
        provider: "test"
      ) { |m| m.name = "Test Model"; m.family = "test" }

      chat_record = session.agent_store.chat.create!(
        model: model,
        project: "abort_test_project",
        run_id: "abort_test_run"
      )

      # Add messages that cost more than $1
      2.times do
        chat_record.messages.create!(
          role: "user",
          content: "expensive",
          input_tokens: 100_000,  # $0.30 per message
          output_tokens: 100_000, # $1.50 per message
          cached_tokens: 0,
          cache_creation_tokens: 0
        )
      end

      # Create a dummy chat record to test with
      record = DummyChat.new(responses: {
        "Test" => "Response"
      })

      # Now create a new chat with session using the dummy record
      chat = session.chat(record: record, tools: [])

      # Test the abort by actually calling ask, which triggers check_abort_cost
      error = assert_raises(AgentC::Errors::AbortCostExceeded) do
        chat.ask("Test")
      end

      assert_equal "project", error.cost_type
      assert error.current_cost > 1.0
      assert_equal 1.0, error.threshold
      assert_match(/Abort: project cost/, error.message)
      assert_match(/exceeds threshold/, error.message)

      # Cleanup
      session.agent_store.message.joins(:chat).where(chats: { project: "abort_test_project" }).delete_all
      session.agent_store.chat.where(project: "abort_test_project").delete_all
    end

    def test_abort_cost_raises_when_run_threshold_exceeded
      # Create session with db_path and abort cost threshold
      session = Session.new(
        project: "abort_test_project_2",
        run_id: "abort_test_run_2",
        agent_db_path: DB_PATH,
        logger: Logger.new(nil),
        max_spend_run: 1.0,
        ruby_llm: {
          bedrock_api_key: "test-key",
          bedrock_secret_key: "test-secret",
          bedrock_region: "us-west-2",
          default_model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        }
      )

      # Create expensive messages
      model = session.agent_store.model.find_or_create_by!(
        model_id: "test-model",
        provider: "test"
      ) { |m| m.name = "Test Model"; m.family = "test" }

      chat_record = session.agent_store.chat.create!(
        model: model,
        project: "abort_test_project_2",
        run_id: "abort_test_run_2"
      )

      # Add messages that cost more than $1
      2.times do
        chat_record.messages.create!(
          role: "user",
          content: "expensive",
          input_tokens: 100_000,  # $0.30 per message
          output_tokens: 100_000, # $1.50 per message
          cached_tokens: 0,
          cache_creation_tokens: 0
        )
      end

      # Create a dummy chat record to test with
      record = DummyChat.new(responses: {
        "Test" => "Response"
      })

      # Now create a new chat with session using the dummy record
      chat = session.chat(record: record, tools: [])

      # Test the abort by actually calling ask, which triggers check_abort_cost
      error = assert_raises(AgentC::Errors::AbortCostExceeded) do
        chat.ask("Test")
      end

      assert_equal "run", error.cost_type
      assert error.current_cost > 1.0
      assert_equal 1.0, error.threshold
      assert_match(/Abort: run cost/, error.message)
      assert_match(/exceeds threshold/, error.message)

      # Cleanup
      session.agent_store.message.joins(:chat).where(chats: { project: "abort_test_project_2" }).delete_all
      session.agent_store.chat.where(project: "abort_test_project_2").delete_all
    end

    def test_abort_cost_does_not_raise_when_under_threshold
      # Create session with db_path and high abort cost threshold
      session = Session.new(
        project: "abort_test_project_3",
        run_id: "abort_test_run_3",
        agent_db_path: DB_PATH,
        logger: Logger.new(nil),
        max_spend_project: 100.0,
        max_spend_run: 100.0,
        ruby_llm: {
          bedrock_api_key: "test-key",
          bedrock_secret_key: "test-secret",
          bedrock_region: "us-west-2",
          default_model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        }
      )

      # Create cheap messages
      model = session.agent_store.model.find_or_create_by!(
        model_id: "test-model",
        provider: "test"
      ) { |m| m.name = "Test Model"; m.family = "test" }

      chat_record = session.agent_store.chat.create!(
        model: model,
        project: "abort_test_project_3",
        run_id: "abort_test_run_3"
      )

      chat_record.messages.create!(
        role: "user",
        content: "cheap",
        input_tokens: 1000,
        output_tokens: 1000,
        cached_tokens: 0,
        cache_creation_tokens: 0
      )

      # Create a dummy chat record to test with
      record = DummyChat.new(responses: {
        "Test" => "Response"
      })

      # Now create a new chat with session using the dummy record
      chat = session.chat(record: record, tools: [])

      # Should not raise - just call ask normally
      response = chat.ask("Test")
      assert_equal "Response", response.content

      # Cleanup
      session.agent_store.message.joins(:chat).where(chats: { project: "abort_test_project_3" }).delete_all
      session.agent_store.chat.where(project: "abort_test_project_3").delete_all
    end
  end
end
