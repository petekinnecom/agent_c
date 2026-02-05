# frozen_string_literal: true

require "ruby_llm"
require "json-schema"

module AgentC
  module Agent
    class Chat
    attr_reader :id, :logger, :tools, :cached_prompts, :session

    def initialize(
      tools: Tools.all,
      cached_prompts: [],
      workspace_dir: nil,
      record:, # Can be used for testing or continuing existing chats
      session: nil
    )
      @session = session
      @logger = session&.config&.logger
      @tools = tools.map do
        if _1.is_a?(Symbol)
          Tools.resolve(
            value: _1,
            available_tools: Tools::NAMES.merge(session&.config&.extra_tools || {}),
            args: {},
            workspace_dir: workspace_dir || session&.config&.workspace_dir
          )
        else
          _1
        end
      end
      @cached_prompts = cached_prompts
      @record_param = record
    end

    def ask(msg)
      record.ask(msg)
    end

    def id
      record.id
    end

    def to_h
      record
        .messages
        .map {
          hash = _1.to_llm.to_h

          if hash.key?(:tool_calls)
            hash[:tool_calls] = hash.fetch(:tool_calls).values.map(&:to_h)
          end

          hash
        }
    end

    NONE = Object.new

    def refine(msg, schema:, times: 2)
      schema = normalize_schema(schema)

      requests = 0
      last_answer = NONE

      while(requests < times)
        requests += 1
        full_msg = (
          if last_answer == NONE
            msg
          else
            I18n.t(
              "agent.chat.refine.system_message",
              prior_answer: last_answer,
              original_message: msg
            )
          end
        )

        last_answer = get_result(full_msg, schema:)
      end

      last_answer
    end

    def get(msg, schema: nil, confirm: 1, out_of: 1)
      requests = 0
      answers = []

      confirmed_answer = NONE

      while(requests < out_of && confirmed_answer == NONE)
        requests += 1
        answers << get_result(msg, schema:)

        current_result = answers.group_by { _1 }.find { _2.count >= confirm }

        if current_result
          confirmed_answer = current_result.first
        end
      end

      if confirmed_answer == NONE
        raise "Unable to confirm an answer:\n#{JSON.pretty_generate(answers)}"
      end

      confirmed_answer
    end

    def messages(...)
      record.messages(...)
    end

    def record
      @record ||= begin
        # If a record was injected (for continuing existing chat), use it
        # Otherwise create a new chat

        # Set up callbacks and tools
        @record_param
          .with_tools(*tools.flatten)
          .on_new_message { log("message start") }
          .on_end_message do |message|
            log("message end: #{serialize_for_log(message).to_json}")
          end
          .on_tool_call { log("tool_call: #{serialize_for_log(_1).to_json}") }
          .on_tool_result { log("tool_result: #{_1}") }
      end
    end

    private

    def normalize_schema(schema)
      if schema.is_a?(Schema::AnyOneOf)
        schema
      elsif schema.is_a?(Array)
        Schema::AnyOneOf.new(*schema)
      else
        Schema::AnyOneOf.new(schema)
      end
    end

    def log(msg)
      logger&.debug("chat-#{id}: #{msg}")
    end

    def serialize_for_log(message)
      hash = message.to_h

      return hash unless hash.key?(:tool_calls)

      hash.merge(
        tool_calls: hash.fetch(:tool_calls).values.map(&:to_h)
      )
    end

    def get_result(msg, schema:)
      tries = 0
      success = false
      json_schema = schema&.to_json_schema&.fetch(:schema)
      result = nil

      message = I18n.t("agent.chat.get_result.json_instructions")

      if schema
        message += I18n.t(
          "agent.chat.get_result.schema_requirement",
          json_schema: json_schema.to_json
        )
      end

      message += I18n.t("agent.chat.get_result.request_wrapper", msg: msg)

      while (!success && tries < 5)
        begin
          response = ask(message)
          json = JSON.parse(response.content.sub(/\A```json/, "").sub(/```\Z/, ""))

          if json_schema.nil? || JSON::Validator.validate(json_schema, json)
            success = true
            result = json
          else
            errors = (
              begin
                JSON::Validator.fully_validate(json_schema, json)
              rescue => e
                e.message
              end
            )

            message = I18n.t(
              "agent.chat.get_result.schema_validation_error",
              errors: errors
            )
          end
        rescue JSON::ParserError => e
          message = I18n.t("agent.chat.get_result.json_parse_error")
        end

        tries += 1
      end

      raise "Failed to get valid response" if !success

      result
    end


    end
  end
end
