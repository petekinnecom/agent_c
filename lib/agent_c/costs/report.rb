# frozen_string_literal: true

module AgentC
  module Costs
    class Report

# Anthropic models	Price per 1,000 input tokens	Price per 1,000 output tokens	Price per 1,000 input tokens (batch)	Price per 1,000 output tokens (batch)	Price per 1,000 input tokens (5m cache write)	Price per 1,000 input tokens (1h cache write)	Price per 1,000 input tokens (cache read)
# Claude Sonnet 4.5	$0.003	$0.015	$0.0015	$0.0075	$0.00375	$0.006	$0.0003
# Claude Sonnet 4.5 - Long Context	$0.006	$0.0225	$0.003	$0.01125	$0.0075	$0.012	$0.0006

      PRICING = {
        normal: {
          input: 3.0,              # $0.003 per 1k tokens
          output: 15.0,            # $0.015 per 1k tokens
          cached_input: 0.3,       # $0.0003 per 1k tokens (cache read)
          cache_creation: 3.75     # $0.00375 per 1k tokens (5m cache write)
        },
        long: {
          input: 6.0,              # $0.006 per 1k tokens
          output: 22.5,            # $0.0225 per 1k tokens
          cached_input: 0.6,       # $0.0006 per 1k tokens (cache read)
          cache_creation: 7.5      # $0.0075 per 1k tokens (5m cache write)
        }
      }.freeze

      LONG_CONTEXT_THRESHOLD = 200_000 # tokens

      def self.call(...)
        new(...).call
      end

      def initialize(agent_store:, project: nil, run_id: nil, out: $stdout)
        @agent_store = agent_store
        @project = project
        @run_id = run_id
        @out = out
        @calculator = Calculator.new
        @printer = Printer.new(out: @out)
      end

      def call
        # Gather all computations based on hierarchy
        computations = []

        # Always compute totals for all projects
        all_messages = fetch_all_messages
        if all_messages.any?
          computations << {
            label: "All Projects",
            stats: @calculator.calculate(all_messages),
            messages: all_messages
          }
        end

        # If project is specified, add project-level computation
        if @project
          project_messages = fetch_project_messages
          if project_messages.any?
            computations << {
              label: "Project: #{@project}",
              stats: @calculator.calculate(project_messages),
              messages: project_messages
            }
          end

          # If run_id is also specified, add run-level computation
          if @run_id
            run_messages = fetch_run_messages
            if run_messages.any?
              computations << {
                label: "Project: #{@project}, Run ID: #{@run_id}",
                stats: @calculator.calculate(run_messages),
                messages: run_messages
              }
            end
          end
        end

        if computations.empty?
          @out.puts "No messages found" if @out
          return []
        end

        # Print to output if provided
        if @out
          @printer.print_hierarchical_report(computations)
        end

        # Return structured data
        computations
      end

      private

      def fetch_all_messages
        @agent_store.message
          .joins(:chat)
          .includes(:model, :chat)
      end

      def fetch_project_messages
        @agent_store.message
          .joins(:chat)
          .where(chats: { project: @project })
          .includes(:model, :chat)
      end

      def fetch_run_messages
        @agent_store.message
          .joins(:chat)
          .where(chats: { project: @project, run_id: @run_id })
          .includes(:model, :chat)
      end

      # Calculator class for computing costs
      class Calculator
        def calculate(messages)
          stats = {
            input_tokens: 0,
            output_tokens: 0,
            cached_tokens: 0,
            cache_creation_tokens: 0,
            input_cost: 0.0,
            output_cost: 0.0,
            cached_cost: 0.0,
            cache_creation_cost: 0.0,
            total_cost: 0.0,
            message_count: messages.count
          }

          messages.each do |message|
            stats[:input_tokens] += message.input_tokens || 0
            stats[:output_tokens] += message.output_tokens || 0
            stats[:cached_tokens] += message.cached_tokens || 0
            stats[:cache_creation_tokens] += message.cache_creation_tokens || 0

            # Determine which pricing tier to use based on total token count
            total_message_tokens = (message.input_tokens || 0) +
                                   (message.cached_tokens || 0) +
                                   (message.cache_creation_tokens || 0)
            pricing = total_message_tokens > LONG_CONTEXT_THRESHOLD ? PRICING[:long] : PRICING[:normal]

            # Calculate cost using appropriate pricing tier
            # Input tokens cost
            if message.input_tokens && message.input_tokens > 0
              cost = (message.input_tokens / 1_000_000.0) * pricing[:input]
              stats[:input_cost] += cost
              stats[:total_cost] += cost
            end

            # Output tokens cost
            if message.output_tokens && message.output_tokens > 0
              cost = (message.output_tokens / 1_000_000.0) * pricing[:output]
              stats[:output_cost] += cost
              stats[:total_cost] += cost
            end

            # Cached tokens cost (cache read)
            if message.cached_tokens && message.cached_tokens > 0
              cost = (message.cached_tokens / 1_000_000.0) * pricing[:cached_input]
              stats[:cached_cost] += cost
              stats[:total_cost] += cost
            end

            # Cache creation tokens cost
            if message.cache_creation_tokens && message.cache_creation_tokens > 0
              cost = (message.cache_creation_tokens / 1_000_000.0) * pricing[:cache_creation]
              stats[:cache_creation_cost] += cost
              stats[:total_cost] += cost
            end
          end

          stats
        end
      end

      # Printer class for formatting output
      class Printer
        def initialize(out: $stdout)
          @out = out
        end

        def print_hierarchical_report(computations)
          computations.each_with_index do |computation, index|
            print_section(computation[:label], computation[:stats], computation[:messages])
            @out.puts "" if index < computations.length - 1
          end
        end

        private

        def print_section(label, stats, messages)
          total_tokens = stats[:input_tokens] + stats[:output_tokens] + stats[:cached_tokens] + stats[:cache_creation_tokens]

          @out.puts <<~REPORT
            ============================================================
            Cost Report: #{label}
            ============================================================
            Messages: #{stats[:message_count]}
            Chats: #{messages.map(&:chat).uniq.count}
            ------------------------------------------------------------
            Token Usage:
              Input tokens:           #{format_number(stats[:input_tokens]).rjust(15)}  $#{format('%.4f', stats[:input_cost]).rjust(8)}
              Output tokens:          #{format_number(stats[:output_tokens]).rjust(15)}  $#{format('%.4f', stats[:output_cost]).rjust(8)}
              Cached tokens:          #{format_number(stats[:cached_tokens]).rjust(15)}  $#{format('%.4f', stats[:cached_cost]).rjust(8)}
              Cache creation tokens:  #{format_number(stats[:cache_creation_tokens]).rjust(15)}  $#{format('%.4f', stats[:cache_creation_cost]).rjust(8)}
            ------------------------------------------------------------
              Total:                  #{format_number(total_tokens).rjust(15)}  $#{format('%.4f', stats[:total_cost]).rjust(8)}
            ============================================================
          REPORT
        end

        def format_number(num)
          num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        end
      end
    end
  end
end
