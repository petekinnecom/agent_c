# frozen_string_literal: true

require "ruby_llm/schema"

module AgentC
  module Schema
    class AnyOneOf
      attr_reader :schemas
      def initialize(*schemas)
        @schemas = schemas
      end

      def to_nested_schema
        to_json_schema.fetch(:schema).fetch(:oneOf)
      end

      def schema_jsons
        @schema_jsons ||= (
          schemas.flat_map do |schema|
            if schema.is_a?(AnyOneOf)
              to_nested_schema
            elsif schema.is_a?(Hash)
              schema
            elsif schema.ancestors.include?(RubyLLM::Schema)
              schema.new.to_json_schema.fetch(:schema)
            else
              raise ArgumentError, "Invalid schema class: #{schema}"
            end
          end
        )
      end

      def to_json_schema
        {
          schema: {
            oneOf: schema_jsons
          }
        }
      end
    end

    class ErrorSchema < RubyLLM::Schema
      string(
        :unable_to_fulfill_request_error,
        description: <<~TXT
          Only fill out this field if you are unable to perform the requested
          task and/or unable to fulfill the other schema provided.

          Fill this in a clear message indicating why you were unable to fulfill
          the request.
        TXT
      )
    end

    def self.result(schema: nil, &)
      # Create the success schema
      success_schema = (
        if block_given? || schema&.respond_to?(:call)
          Class.new(RubyLLM::Schema) do
            instance_exec(&) if block_given?
            instance_exec(&schema) if schema
          end
        else
          schema
        end
      )

      AnyOneOf.new(success_schema, ErrorSchema)
    end
  end
end
