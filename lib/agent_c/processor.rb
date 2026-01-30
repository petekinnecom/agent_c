# frozen_string_literal: true

module AgentC
  class Processor
    Handler = Data.define(:task, :handler) do
      def call
        handler.call(task)
        if task.pending?
          raise "Task Pending error"
        end
      end
    end

    attr_reader :context, :handlers
    def initialize(context:, handlers:)
      @context = context
      @handlers = handlers.transform_keys(&:to_s)
    end

    def add_task(record, handler)
      raise ArgumentError.new("invalid handler") unless handlers.include?(handler.to_s)

      store.task.find_or_create_by!(record:, handler:)
    end

    def call(&)
      raise "must provide at least one workspace" if workspace_count == 0

      if workspace_count == 1
        call_synchronous(context.workspaces.first, &)
      else
        call_asynchronous(&)
      end
    end

    def abort!
      @abort = true
    end

    def abort?
      @abort
    end

    private

    def call_asynchronous(&)
      error = nil

      Async { |task|
        semaphore = Async::Semaphore.new(workspace_count)

        context.workspaces.map  { |workspace|
          semaphore.async do
            call_synchronous(workspace, &)
          rescue => e
            abort!
            error = e
          end
        }

      }.wait

      raise error if error
    end

    def call_synchronous(workspace)
      while(handler = next_handler(workspace))
        handler.call
        yield if block_given? # allow the invoker to do work inbetween handler calls
      end
    end

    def next_handler(workspace)
      return nil if abort?

      task = (
        store
          .task
          .where("workspace_id = ? OR workspace_id IS NULL", workspace.id)
          .order("created_at ASC")
          .find_by(status: :pending)
      )

      if task
        task.update!(workspace:) unless task.workspace
        Handler.new(task:, handler: handlers.fetch(task.handler))
      end
    end

    def workspace_count
      @workspace_count ||= context.workspaces.count
    end

    def store
      context.store
    end
  end
end
