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
      !@raw_response.key?("unable_to_fulfill_request_error")
    end

    def status
      if success?
        "success"
      else
        "error"
      end
    end

    def data
      raise "Cannot call data on failed response. Use error_message instead." unless success?

      raw_response
    end

    def error_message
      raise "Cannot call error_message on successful response. Use data instead." if success?

      raw_response.fetch("unable_to_fulfill_request_error")
    end
    end
  end
end
