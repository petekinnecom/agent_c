# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "fileutils"

require_relative "../lib/autoload"

# Require the base gems first
require "agent_c/test_helpers"

module TestHelpers
  include AgentC::TestHelpers

  def dummy_chat_factory(responses)
    ->(**_kwargs) { AgentC::TestHelpers::DummyChat.new(responses: responses) }
  end
end
