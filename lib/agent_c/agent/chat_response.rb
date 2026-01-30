# frozen_string_literal: true

module AgentC
  module Agent
    class ChatResponse
    attr_reader :chat_id, :raw_response

    def initialize(chat_id:, raw_response:)
      @chat_id = chat_id
      @raw_response = raw_response
    end

    def success?
      status == "success"
    end

    def status
      @raw_response.fetch("status")
    end

    def data
      raise "Cannot call data on failed response. Use error_message instead." unless success?
      raw_response.reject { |k, _| k == "status" }
    end

    def error_message
      raise "Cannot call error_message on successful response. Use data instead." if success?
      raw_response.fetch("message")
    end
    end
  end
end
