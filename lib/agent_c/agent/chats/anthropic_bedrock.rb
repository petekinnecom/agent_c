# frozen_string_literal: true

module AgentC
  module Agent
    module Chats
      module AnthropicBedrock
      def self.create(project:, run_id:, prompts:, agent_store:, ruby_llm_context:)
        ruby_llm_config = ruby_llm_context.config

        chat = agent_store.chat
          .create!(
            model: agent_store.model.find_or_create_by!(
              model_id: ruby_llm_config.default_model,
              provider: "bedrock"
            ) { |m|
              m.name = "Claude Sonnet 4.5"
              m.family = "claude"
            },
            project: project,
            run_id: run_id
          )

        # Set the context on the chat record so to_llm can use it
        chat.define_singleton_method(:context) { ruby_llm_context }

        chat.tap { |chat|
          if prompts.any?
            # WARN -- RubyLLM: Anthropic's Claude implementation only supports
            # a single system message. Multiple system messages will be
            # combined into one.
            shared_prompt = prompts.join("\n---\n")
            chat.messages.create!(
              role: :system,
              content_raw: [
                {
                  "type" => "text",
                  "text" => shared_prompt,
                  "cache_control" => { "type" => "ephemeral" }
                }
              ]
            )
          end
        }
      end
      end
    end
  end
end
