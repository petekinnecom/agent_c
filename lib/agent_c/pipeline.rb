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
        step(name) do
          resolved_params = (
            if block
              instance_exec(&block)
            elsif params.empty?
              i18n_attributes = (
                if record.respond_to?(:i18n_attributes)
                  record.i18n_attributes
                else
                  record.attributes
                end
              )

              {
                tool_args: {
                  workspace_dir: workspace.dir,
                  env: workspace.env,
                },
                cached_prompt: I18n.t("#{name}.cached_prompts"),
                prompt: I18n.t("#{name}.prompt", **i18n_attributes.symbolize_keys),
                tools: I18n.t("#{name}.tools"),
                schema: -> {
                  next unless I18n.exists?("#{name}.response_schema")

                  I18n.t("#{name}.response_schema").each do |name, spec|
                    extra = spec.except(:required, :description, :type)

                    if extra.key?(:of)
                      extra[:of] = extra[:of]&.to_sym
                    end

                    send(
                      spec.fetch(:type, "string"),
                      name,
                      required: spec.fetch(:required, true),
                      description: spec.fetch(:description),
                      **extra
                    )
                  end
                }
              }
            else
              i18n_attributes = (
                if record.respond_to?(:i18n_attributes)
                  record.i18n_attributes
                else
                  record.attributes
                end
              )

              {
                tool_args: {
                  workspace_dir: workspace.dir,
                  env: workspace.env,
                }
              }.tap { |hash|
                if params.key?(:prompt_key)
                  hash[:prompt] = I18n.t(params[:prompt_key],  **i18n_attributes.symbolize_keys)
                end

                if params.key?(:cached_prompt_keys)
                  hash[:cached_prompt] = params[:cached_prompt_keys].map { I18n.t(_1) }
                end
              }.merge(params.except(:cached_prompt_keys, :prompt_key))
            end
          )

          result = session.prompt(
            on_chat_created: -> (id) { task.chat_ids << id},
            **resolved_params
          )

          if result.success?
            task.record.update!(result.data)
          else
            task.fail!(result.error_message)
          end
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

    def repo
      @repo ||= @git.call(workspace.dir)
    end

    def log(msg)
      logger.info("task: #{task.id}: #{msg}")
    end

    def logger
      session.logger
    end
  end
end
