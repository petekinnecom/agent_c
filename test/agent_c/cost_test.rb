# frozen_string_literal: true

require "test_helper"

module AgentC
  class CostTest < Minitest::Test
    def setup
      @logger = Logger.new(STDOUT)
      @logger.level = Logger::WARN

      @session = Session.new(
        agent_db_path: DB_PATH,
        logger: @logger,
        project: "test_project",
        run_id: "test_run_123",
        ruby_llm: {
          bedrock_api_key: "test-key",
          bedrock_secret_key: "test-secret",
          bedrock_region: "us-west-2",
          default_model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        }
      )

      # Clean up test data before each test
      @session.agent_store.message.joins(:chat).where(chats: { project: "test_project" }).delete_all
      @session.agent_store.chat.where(project: "test_project").delete_all
    end

    def teardown
      # Clean up test data after each test
      @session.agent_store.message.joins(:chat).where(chats: { project: "test_project" }).delete_all
      @session.agent_store.chat.where(project: "test_project").delete_all
    end

    def test_calculate_returns_cost_object
      cost = @session.cost

      assert_instance_of Costs::Data, cost
      assert_respond_to cost, :project
      assert_respond_to cost, :run
    end

    def test_calculate_with_no_messages
      cost = @session.cost

      assert_equal 0.0, cost.project
      assert_equal 0.0, cost.run
    end

    def test_calculate_with_project_messages
      # Create a chat with messages for the project
      model = @session.agent_store.model.find_or_create_by!(
        model_id: "test-model",
        provider: "test"
      ) { |m| m.name = "Test Model"; m.family = "test" }

      chat = @session.agent_store.chat.create!(
        model: model,
        project: "test_project",
        run_id: "other_run"
      )

      # Add a message with token usage
      # Using tokens below 200k threshold to use normal pricing
      message = chat.messages.create!(
        role: "user",
        content: "test",
        input_tokens: 100_000,  # 100k tokens = $0.30 (normal pricing)
        output_tokens: 100_000, # 100k tokens = $1.50 (normal pricing)
        cached_tokens: 0,
        cache_creation_tokens: 0
      )

      cost = @session.cost

      # Project should have cost from all runs
      # $0.30 + $1.50 = $1.80
      assert_equal 1.8, cost.project

      # Run should have no cost (different run_id)
      assert_equal 0.0, cost.run
    end

    def test_calculate_with_run_messages
      # Create a chat with messages for the specific run
      model = @session.agent_store.model.find_or_create_by!(
        model_id: "test-model",
        provider: "test"
      ) { |m| m.name = "Test Model"; m.family = "test" }

      chat = @session.agent_store.chat.create!(
        model: model,
        project: "test_project",
        run_id: "test_run_123"
      )

      # Add a message with token usage
      # Using tokens below 200k threshold to use normal pricing
      message = chat.messages.create!(
        role: "user",
        content: "test",
        input_tokens: 100_000,  # 100k tokens = $0.30 (normal pricing)
        output_tokens: 100_000, # 100k tokens = $1.50 (normal pricing)
        cached_tokens: 0,
        cache_creation_tokens: 0
      )

      cost = @session.cost

      # Both project and run should have the same cost
      # $0.30 + $1.50 = $1.80
      assert_equal 1.8, cost.project
      assert_equal 1.8, cost.run
    end

    def test_calculate_with_multiple_runs
      # Create messages for different runs
      model = @session.agent_store.model.find_or_create_by!(
        model_id: "test-model",
        provider: "test"
      ) { |m| m.name = "Test Model"; m.family = "test" }

      chat1 = @session.agent_store.chat.create!(
        model: model,
        project: "test_project",
        run_id: "test_run_123"
      )
      chat1.messages.create!(
        role: "user",
        content: "test1",
        input_tokens: 100_000,  # 100k tokens = $0.30 (normal pricing)
        output_tokens: 0,
        cached_tokens: 0,
        cache_creation_tokens: 0
      )

      chat2 = @session.agent_store.chat.create!(
        model: model,
        project: "test_project",
        run_id: "other_run"
      )
      chat2.messages.create!(
        role: "user",
        content: "test2",
        input_tokens: 100_000,  # 100k tokens = $0.30 (normal pricing)
        output_tokens: 0,
        cached_tokens: 0,
        cache_creation_tokens: 0
      )

      cost = @session.cost

      # Project should include all runs
      # $0.30 + $0.30 = $0.60
      assert_in_delta 0.6, cost.project, 0.001

      # Run should only include test_run_123
      # $0.30
      assert_in_delta 0.3, cost.run, 0.001
    end

    def test_calculate_with_cached_tokens
      model = @session.agent_store.model.find_or_create_by!(
        model_id: "test-model",
        provider: "test"
      ) { |m| m.name = "Test Model"; m.family = "test" }

      chat = @session.agent_store.chat.create!(
        model: model,
        project: "test_project",
        run_id: "test_run_123"
      )

      # Add a message with cached tokens (below 200k threshold for normal pricing)
      chat.messages.create!(
        role: "user",
        content: "test",
        input_tokens: 0,
        output_tokens: 0,
        cached_tokens: 100_000,  # 100k tokens = $0.03 (normal pricing)
        cache_creation_tokens: 50_000  # 50k tokens = $0.1875 (normal pricing)
      )

      cost = @session.cost

      # $0.03 + $0.1875 = $0.2175
      assert_equal 0.2175, cost.project
      assert_equal 0.2175, cost.run
    end
  end
end
