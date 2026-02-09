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

    def call(&)
      processor.call(&)
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

      out.puts "Total: #{tasks.count}"
      out.puts "Succeeded: #{succeeded_count}"
      out.puts "Pending: #{pending_count}"
      out.puts "Failed: #{failed_count}"

      # Calculate time span
      if tasks.any?
        created_ats = tasks.map(&:created_at).compact
        updated_ats = tasks.map(&:updated_at).compact

        if created_ats.any? && updated_ats.any?
          earliest = created_ats.min
          latest = updated_ats.max
          time_span_seconds = (latest - earliest).to_i

          hours = time_span_seconds / 3600
          minutes = (time_span_seconds % 3600) / 60
          seconds = time_span_seconds % 60

          out.puts "Time: #{hours} hrs, #{minutes} mins, #{seconds} secs"
        end
      end

      # Count worktrees
      worktree_count = store.workspace.count
      out.puts "Worktrees: #{worktree_count}"

      cost_data = session.cost
      out.puts "Run cost: $#{'%.2f' % cost_data.run}"
      out.puts "Project total cost: $#{'%.2f' % cost_data.project}"

      # Cost and time per task
      if tasks.count > 0
        cost_per_task = (cost_data.run * worktree_count.to_f) / tasks.count.to_f
        out.puts "Cost per task: $#{'%.2f' % cost_per_task}"

        if tasks.any? && created_ats&.any? && updated_ats&.any?
          total_minutes = time_span_seconds / 60.0
          # Account for parallelism: if we have multiple worktrees,
          # tasks could run in parallel
          effective_minutes = worktree_count > 0 ? total_minutes / worktree_count : total_minutes
          minutes_per_task = effective_minutes / tasks.count
          out.puts "Minutes per task: #{'%.2f' % minutes_per_task}"
        end
      end

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
