# frozen_string_literal: true

module AgentC
  class Pipeline
    def self.call(...)
      new(...).tap(&:call)
    end

    attr_reader :session, :task
    def initialize(
      session:,
      task:,
      git: ->(dir) { Utils::Git.new(dir) }
    )
      @session = session
      @task = task
      @git = git
    end

    Step = Data.define(:name, :block)

    class << self
      def on_failures
        @on_failures ||= []
      end

      def steps
        @steps ||= []
      end

      def on_failure(&block)
        self.on_failures << block
      end

      def step(name, &block)
        self.steps << Step.new(name:, block:)
      end

      def agent_step(name, **params, &block)
        raise ArgumentError.new("Can't pass block and params") if params.any? && block

        step(name) do
          agent = Pipelines::Agent.new(self)
          agent.agent_step(name, **params, &block)
        end
      end
    end

    def call
      raise "Task.workspace is nil" unless task.workspace

      log("start")

      while(task.pending?)
        break if task.failed?

        step = self.class.steps.find { !task.completed_steps.include?(_1.name.to_s) }
        break if step.nil?

        @rewind_to = nil

        store.transaction do
          log_prefix = "step: '#{step.name}'"

          log("#{log_prefix} start")

          instance_exec(&step.block)

          if task.failed?
            log("#{log_prefix} failed, executing on_failures")
            self.class.on_failures.each { instance_exec(&_1)}
          elsif @rewind_to
            matching_steps = task.completed_steps.select { _1 == @rewind_to }

            if matching_steps.count == 0
              raise ArgumentError, <<~TXT
                Cannot rewind to a step that's not been completed yet:

                rewind_to!(#{@rewind_to.inspect})
                completed_steps: #{task.completed_steps.inspect}
              TXT
            elsif matching_steps.count > 1
              raise ArgumentError, <<~TXT
                Cannot rewind to a step with a non-distinct name. The step
                name appears multiple times:

                rewind_to!(#{@rewind_to.inspect})
                completed_steps: #{task.completed_steps.inspect}
              TXT
            end

            log("#{log_prefix} rewind_to! #{@rewind_to.inspect}")
            task
              .completed_steps
              .index(@rewind_to)
              .then { task.update!(completed_steps: task.completed_steps[0..._1]) }
          else
            log("#{log_prefix} done")
            task.completed_steps << step.name.to_s
          end
        end
      end

      store.transaction do
        log("done")
        task.done! unless task.failed?
      end
    rescue => e
      store.transaction do
        log("Exception raised, running on_failures")
        task.fail!(["#{e.class.name}:#{e.message}", e.backtrace].join("\n"))
        self.class.on_failures.each { instance_exec(&_1) }
      end
    end

    def workspace
      task.workspace
    end

    def record
      task.record
    end

    def store
      task.store
    end

    def rewind_to!(step)
      @rewind_to = step.to_s
    end

    def git
      @_git ||= @git.call(workspace.dir)
    end

    def log(msg)
      logger.info("task: #{task.id}: #{msg}")
    end

    def logger
      session.logger
    end

  end
end
