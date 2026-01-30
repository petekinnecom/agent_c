# frozen_string_literal: true

require "test_helper"

class RealAgentsTest < Minitest::Test
  def setup
    # Skip setup if AWS credentials are not available
    unless ENV["AWS_ACCESS_KEY_ID"] && ENV["AWS_SECRET_ACCESS_KEY"] && ENV["AWS_SESSION_TOKEN"]
      skip "AWS credentials not available"
    end

    unless ENV.key?("RUN_REAL_AGENT_TESTS")
      skip "skipping real agent tests unless RUN_REAL_AGENT_TESTS env var is set to avoid wasting tokens"
    end

    @logger = Logger.new(STDOUT)
    @logger.level = Logger::WARN

    @session = Session.new(
      agent_db_path: DB_PATH,
      logger: @logger,
      project: "real_agents_test",
      ruby_llm: {
        bedrock_api_key: ENV.fetch("AWS_ACCESS_KEY_ID"),
        bedrock_secret_key: ENV.fetch("AWS_SECRET_ACCESS_KEY"),
        bedrock_session_token: ENV.fetch("AWS_SESSION_TOKEN"),
        bedrock_region: "us-west-2",
        default_model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
      }
    )
  end


  def test_cached_prompts_result_in_cached_tokens__raw_ruby_llm
    skip "don't waste tokens"
    cached_prompt = "You are a spanish speaker. Respond in spanish!" * 100

    chat_1 = RubyLLM.chat
    chat_1.add_message(
      role: :system,
      content: RubyLLM::Providers::Anthropic::Content.new(
        cached_prompt,
        cache: true
      )
    )
    response_1 = chat_1.ask("What is your favorite tree?")

    chat_2 = RubyLLM.chat
    chat_2.add_message(
      role: :system,
      content: RubyLLM::Providers::Anthropic::Content.new(
        cached_prompt,
        cache: true
      )
    )
    response_2 = chat_2.ask("What is your favorite car?")

    assert response_1.cache_creation_tokens > 0, response_1.cache_creation_tokens
    assert response_2.cached_tokens > 0, response_2.cached_tokens
  end

  def test_cached_prompts_result_in_cached_tokens__using_agent
    skip "don't waste tokens"
    cached_prompt = "You are a spanish speaker. Respond in spanish!" * 100

    chat_1 = @session.chat(cached_prompts: [cached_prompt])
    response_1 = chat_1.ask("What is your favorite tree?")

    chat_2 = @session.chat(cached_prompts: [cached_prompt])
    response_2 = chat_2.ask("What is your favorite car?")

    assert response_2.cached_tokens > 0, response_2.cached_tokens
  end

end
