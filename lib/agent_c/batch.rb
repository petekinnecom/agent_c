# frozen_string_literal: true

module AgentC
  class Batch
    def initialize(
      store:,
      workspace: nil,
      repo: nil,
      session:,
      record_type:,
      pipeline:,
      git: ->(dir) { Utils::Git.new(dir) }
    )
      # for context
      @store_config = store
      @workspace_config = workspace
      @repo_config = repo
      @session_config = session

      # for Batch
      @record_type = record_type
      @pipeline_class = pipeline
      @git = git
    end

    def call
      processor.call
    end

    def add_task(record)
      processor.add_task(record, @record_type)
    end

    def abort!
      processor.abort!
    end

    def report
      out = StringIO.new

      tasks = store.task.all
      succeeded_count = tasks.count { |task| task.done? }
      pending_count = tasks.count { |task| task.pending? }
      failed_count = tasks.count { |task| task.failed? }

      out.puts "Succeeded: #{succeeded_count}"
      out.puts "Pending: #{pending_count}"
      out.puts "Failed: #{failed_count}"

      cost_data = session.cost
      out.puts "Run cost: $#{'%.2f' % cost_data.run}"
      out.puts "Project total cost: $#{'%.2f' % cost_data.project}"

      if failed_count > 0
        out.puts "\nFirst #{[failed_count, 3].min} failed task(s):"
        tasks.select { |task| task.failed? }.first(3).each do |task|
          out.puts "- #{task.error_message}"
        end
      end

      out.string
    end

    def store
      context.store
    end

    def workspaces
      context.workspaces
    end

    def session
      context.session
    end

    private

    def processor
      @processor ||= Processor.new(
        context:,
        handlers: {
          @record_type => ->(task) {
            @pipeline_class.call(
              session:,
              task:,
              git: @git
            )
          }
        }
      )
    end

    def context
      @context ||= Context.new(
        store: @store_config,
        session: @session_config,
        workspace: @workspace_config,
        repo: @repo_config,
      )
    end
  end
end
