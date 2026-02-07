# frozen_string_literal: true

module AgentC
  module Pipelines
    class Agent
      attr_reader :pipeline
      def initialize(pipeline)
        @pipeline = pipeline
      end

      def agent_step(name, **params, &block)
        result = process_prompt(name, **params, &block)

        if result.success?
          task.record.update!(result.data)
        else
          task.fail!(result.error_message)
        end

      end

      private

      def record
        pipeline.record
      end

      def task
        pipeline.task
      end

      def workspace
        pipeline.workspace
      end

      def session
        pipeline.session
      end

      def process_prompt(name, **params, &block)
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

        session.prompt(
          on_chat_created: -> (id) { task.chat_ids << id},
          **resolved_params
        )
      end
    end
  end
end
