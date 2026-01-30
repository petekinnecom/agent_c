# frozen_string_literal: true

require "test_helper"

module AgentC
  class ErrorsTest < Minitest::Test
    def test_base_is_standard_error
      assert_kind_of StandardError, Errors::Base.new
    end

    def test_abort_cost_exceeded_inherits_from_base
      error = Errors::AbortCostExceeded.new(
        cost_type: "project",
        current_cost: 100.0,
        threshold: 50.0
      )

      assert_kind_of Errors::Base, error
      assert_kind_of StandardError, error
    end

    def test_abort_cost_exceeded_has_attributes
      error = Errors::AbortCostExceeded.new(
        cost_type: "project",
        current_cost: 100.0,
        threshold: 50.0
      )

      assert_equal "project", error.cost_type
      assert_equal 100.0, error.current_cost
      assert_equal 50.0, error.threshold
    end

    def test_abort_cost_exceeded_message_format
      error = Errors::AbortCostExceeded.new(
        cost_type: "project",
        current_cost: 100.5,
        threshold: 50.25
      )

      assert_equal "Abort: project cost $100.5 exceeds threshold $50.25", error.message
    end

    def test_abort_cost_exceeded_with_run_type
      error = Errors::AbortCostExceeded.new(
        cost_type: "run",
        current_cost: 75.0,
        threshold: 60.0
      )

      assert_equal "run", error.cost_type
      assert_match(/Abort: run cost/, error.message)
    end
  end
end
