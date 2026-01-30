# frozen_string_literal: true

require "ruby_llm"
require "ruby_llm/active_record/acts_as"

module AgentC
  module Db
    class Store < VersionedStore::Base
      record(:model) do
        schema :models do |t|
          t.string :model_id, null: false
          t.string :name, null: false
          t.string :provider, null: false
          t.string :family
          t.datetime :model_created_at
          t.integer :context_window
          t.integer :max_output_tokens
          t.date :knowledge_cutoff
          t.json :modalities, default: {}
          t.json :capabilities, default: []
          t.json :pricing, default: {}
          t.json :metadata, default: {}
          t.timestamps

          t.index [:provider, :model_id], unique: true
          t.index :provider
          t.index :family
        end

        include RubyLLM::ActiveRecord::ActsAs
        acts_as_model chats: :chats, chat_class: class_name(:chat)
      end

      record(:chat) do
        schema :chats do |t|
          t.references :model, foreign_key: true
          t.string :project
          t.string :run_id
          t.timestamps
        end

        include RubyLLM::ActiveRecord::ActsAs

        acts_as_chat(
          messages: :messages,
          message_class: class_name(:message),
          messages_foreign_key: :chat_id,
          model: :model,
          model_class: class_name(:model),
          model_foreign_key: :model_id
        )

        belongs_to(
          :model,
          class_name: class_name(:model),
          required: false
        )

        validates :model, presence: true

        def messages_hash
          messages
            .map {
              hash = _1.to_llm.to_h

              if hash.key?(:tool_calls)
                hash[:tool_calls] = hash.fetch(:tool_calls).values.map(&:to_h)
              end

              if hash.key?(:content) && !hash[:content].is_a?(String)
                hash[:content] = hash[:content].to_h
              end

              hash
            }
        end
      end

      record(:message) do
        schema :messages do |t|
          t.references :chat, null: false, foreign_key: true
          t.references :model, foreign_key: true
          t.references :tool_call, foreign_key: true
          t.string :role, null: false
          t.text :content
          t.json :content_raw
          t.integer :input_tokens
          t.integer :output_tokens
          t.integer :cached_tokens
          t.integer :cache_creation_tokens
          t.timestamps

          t.index :role
        end

        include RubyLLM::ActiveRecord::ActsAs

        acts_as_message(
          chat: :chat,
          chat_class: class_name(:chat),
          chat_foreign_key: :chat_id,
          tool_calls: :tool_calls,
          tool_call_class: class_name(:tool_call),
          tool_calls_foreign_key: :message_id,
          model: :model,
          model_class: class_name(:model),
          model_foreign_key: :model_id
        )

        belongs_to(
          :chat,
          class_name: class_name(:chat),
          required: false
        )

        belongs_to(
          :model,
          class_name: class_name(:model),
          required: false
        )

        belongs_to(
          :tool_call,
          class_name: class_name(:tool_call),
          required: false
        )

        validates :role, presence: true
        validates :chat, presence: true
      end

      record(:tool_call) do
        schema :tool_calls do |t|
          t.references :message, null: false, foreign_key: true
          t.string :tool_call_id, null: false
          t.string :name, null: false
          t.json :arguments, default: {}
          t.timestamps

          t.index :tool_call_id, unique: true
          t.index :name
        end

        include RubyLLM::ActiveRecord::ActsAs

        acts_as_tool_call(
          message: :message,
          message_class: class_name(:message),
          message_foreign_key: :message_id,
          result: :result,
          result_class: class_name(:message)
        )

        belongs_to(
          :message,
          class_name: class_name(:message),
          required: false
        )
      end
    end
  end
end
