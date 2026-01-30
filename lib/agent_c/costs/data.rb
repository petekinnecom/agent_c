# frozen_string_literal: true

module AgentC
  module Costs
    class Data
      attr_reader :project, :run

      def initialize(project:, run:)
        @project = project
        @run = run
      end

      def self.calculate(agent_store:, project:, run_id: nil)
        calculator = Report::Calculator.new

        # Calculate project-level cost
        project_messages = agent_store.message
          .joins(:chat)
          .where(chats: { project: project })
          .includes(:model, :chat)
        project_stats = calculator.calculate(project_messages)
        project_cost = project_stats[:total_cost]

        # Calculate run-level cost
        run_cost = 0.0
        if run_id
          run_messages = agent_store.message
            .joins(:chat)
            .where(chats: { project: project, run_id: run_id })
            .includes(:model, :chat)
          run_stats = calculator.calculate(run_messages)
          run_cost = run_stats[:total_cost]
        end

        new(project: project_cost, run: run_cost)
      end
    end
  end
end
