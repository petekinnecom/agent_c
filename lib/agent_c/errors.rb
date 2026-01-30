# frozen_string_literal: true

module AgentC
  module Errors
    class Base < StandardError
    end

    class AbortCostExceeded < Base
      attr_reader :cost_type, :current_cost, :threshold

      def initialize(cost_type:, current_cost:, threshold:)
        @cost_type = cost_type
        @current_cost = current_cost
        @threshold = threshold
        super("Abort: #{cost_type} cost $#{current_cost.round(2)} exceeds threshold $#{threshold.round(2)}")
      end
    end
  end
end
