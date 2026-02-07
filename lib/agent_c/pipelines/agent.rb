# frozen_string_literal: true

module AgentC
  module Pipelines
    class Agent
      attr_reader :pipeline
      def initialize(pipeline)
        @pipeline = pipeline
      end

      def agent_review_loop(
        name,
        max_tries: 10,
        implement: [],
        iterate: implement,
        review:
      )
        implement = Array(implement)
        iterate = Array(iterate)
        review = Array(review)

        unless implement.any? || iterate.any?
          raise ArgumentError.new("Must pass implement or iterate prompts")
        end

        tries = 0
        review_passed = false
        feedbacks = []

        while(tries < max_tries && !review_passed && !task.failed?)
          if tries == 0
            implement.each do |name|
              apply_prompt(name)
              break if task.failed?
            end
          else
            iterate.each do |name|
              apply_prompt(
                name,
                additional_i18n_attributes: {
                  feedback: feedbacks.join("\n---\n")
                }
              )
              break if task.failed?
            end
          end

          tries += 1

          unless task.failed?
            feedbacks = []
            diff = git.diff
            review.each do |name|
              params = i18n_params(
                name,
                additional_i18n_attributes: {
                  diff:
                },
              ).merge(
                schema: -> {
                  boolean(:approved)
                  string(:feedback)
                },
              )

              result = prompt(name, **params)

              if result.success?
                if !result.data.fetch("approved")
                  feedbacks << result.data.fetch("feedback")
                end
              else
                task.fail!(result.error_message)
              end
            end

            if record.respond_to?(:add_review)
              record.add_review(diff:, feedbacks:)
            end

            review_passed = feedbacks.empty?
          end
        end
      end

      def agent_step(name, **params, &block)
        apply_prompt(name, **params, &block)
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

      def git
        pipeline.git
      end

      def apply_prompt(...)
        result = prompt(...)

        if result.success?
          task.record.update!(result.data)
        else
          task.fail!(result.error_message)
        end
      end

      def prompt(
        name,
        additional_i18n_attributes: {},
        **params,
        &block
      )
        resolved_params = (
          if block
            instance_exec(&block)
          elsif params.empty?
            i18n_params(name, additional_i18n_attributes:)
          else
            i18n_attributes = (
              if record.respond_to?(:i18n_attributes)
                record.i18n_attributes
              else
                record.attributes
              end
            ).merge(additional_i18n_attributes)

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

      def i18n_params(name, additional_i18n_attributes: {})
        i18n_attributes = (
          if record.respond_to?(:i18n_attributes)
            record.i18n_attributes
          else
            record.attributes
          end
        ).merge(additional_i18n_attributes)

        {
          tool_args: {
            workspace_dir: workspace.dir,
            env: workspace.env,
          },
          cached_prompt: (
            if I18n.exists?("#{name}.cached_prompts")
              I18n.t("#{name}.cached_prompts")
            else
              []
            end
          ),
          prompt: I18n.t("#{name}.prompt", **i18n_attributes.symbolize_keys),
          tools: (
            if I18n.exists?("#{name}.tools")
              I18n.t("#{name}.tools")
            else
              []
            end
          ),
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
      rescue => e
        binding.irb
      end
    end
  end
end
