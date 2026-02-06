# frozen_string_literal: true

require_relative "../test_helper"
require "json-schema"

module AgentC
  class SchemaTest < Minitest::Test
    def test_result_with_success_status
      # Create a schema using Schema.result with custom fields
      test_schema = Schema.result do
        string(:data, description: "The result data")
      end

      json_schema = test_schema&.to_json_schema&.fetch(:schema)

      # Test successful case - just the data fields, no status
      result = { data: "test data" }
      assert JSON::Validator.validate(json_schema, result)

      # Verify data field is required
      invalid_result = {}
      refute JSON::Validator.validate(json_schema, invalid_result)
    end

    def test_result_with_error_status
      # Create a schema using Schema.result
      test_schema = Schema.result do
        string(:data, description: "The result data")
      end

      json_schema = test_schema&.to_json_schema&.fetch(:schema)

      # Test error case
      result = { unable_to_fulfill_request_error: "Something went wrong" }
      assert JSON::Validator.validate(json_schema, result)
      # Verify unable_to_fulfill_request_error field is required for error
      invalid_result = {}
      refute JSON::Validator.validate(json_schema, invalid_result)
    end

    def test_result_with_multiple_fields
      # Create a schema with multiple custom fields
      test_schema = Schema.result do
        string(:name, description: "User name")
        integer(:age, description: "User age")
        array(:hobbies, of: :string, description: "List of hobbies")
      end

      json_schema = test_schema&.to_json_schema&.fetch(:schema)

      # Test with all fields present - no status field
      result = {
        name: "John",
        age: 30,
        hobbies: ["reading", "coding"]
      }
      assert JSON::Validator.validate(json_schema, result)
    end

    def test_result_invalid_mixed_response
      test_schema = Schema.result do
        string(:data, description: "The result data")
      end

      json_schema = test_schema&.to_json_schema&.fetch(:schema)

      # Test with both success and error fields (invalid)
      result = { data: "test", unable_to_fulfill_request_error: "error" }
      refute JSON::Validator.validate(json_schema, result)
    end

    def test_result_returns_class
      test_schema = Schema.result do
        string(:data)
      end

      # Verify that Schema.result returns an AnyOneOf instance
      assert test_schema.is_a?(Schema::AnyOneOf)
      # Verify it has the to_json_schema method
      assert test_schema.respond_to?(:to_json_schema)
      # Verify the schema has the expected structure
      json_schema = test_schema.to_json_schema[:schema]
      assert json_schema[:oneOf]
      assert_equal 2, json_schema[:oneOf].length # success, error, deferred
    end

    def test_result_with_hash_schema
      # Create a JSON schema as a Hash
      success_hash_schema = {
        type: "object",
        properties: {
          result: { type: "string" },
          count: { type: "integer" }
        },
        required: ["result"]
      }

      test_schema = Schema.result(schema: success_hash_schema)

      json_schema = test_schema&.to_json_schema&.fetch(:schema)

      # Test successful case with Hash schema
      result = { result: "completed", count: 42 }
      assert JSON::Validator.validate(json_schema, result)

      # Verify required fields
      invalid_result = { count: 42 }
      refute JSON::Validator.validate(json_schema, invalid_result)
    end

    def test_result_with_hash_schema_still_allows_error
      # Create a JSON schema as a Hash
      success_hash_schema = {
        type: "object",
        properties: {
          data: { type: "string" }
        },
        required: ["data"]
      }

      test_schema = Schema.result(schema: success_hash_schema)
      json_schema = test_schema&.to_json_schema&.fetch(:schema)

      # Test error case still works
      result = { unable_to_fulfill_request_error: "Something went wrong" }
      assert JSON::Validator.validate(json_schema, result)
    end
  end
end
