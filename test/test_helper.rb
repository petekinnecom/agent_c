# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "logger"

# Test helper to set up common test environment
ENV["RACK_ENV"] = "test"

require "agent_c"

# Define test database path
DB_PATH = File.expand_path("../tmp/db/test.sqlite3", __dir__)

# Optional: Add minitest reporters for better output
begin
  require "minitest/reporters"
  Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
rescue LoadError
  # minitest/reporters not available, use default output
end

module AgentC
  class UnitTest < Minitest::Test
    include TestHelpers
  end
end
