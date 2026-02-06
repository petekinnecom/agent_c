# frozen_string_literal: true

require_relative "../test_helper"
require "json-schema"

module AgentC
  class PipelineCustomToolTest < UnitTest
    def setup
      @store_class = Class.new(VersionedStore::Base) do
        include AgentC::Store

        record(:my_record) do
          schema do |t|
            t.string(:attr_1)
          end

          has_many(
            :tasks,
            class_name: class_name(:task)
          )
        end
      end

      @store = @store_class.new(dir: Dir.mktmpdir)
      @workspace = @store.workspace.create!(
        dir: "/tmp/example",
        env: { "ENV_VALUE" => "1" }
      )
    end

    def test_pipeline_custom_tool
      custom_tool_auto_initialized = Class.new(RubyLLM::Tool) do
        attr_reader :workspace_dir, :env
        def initialize(workspace_dir:, env:)
          @workspace_dir = workspace_dir
          @env = env
        end

        def inspect
          "custom tool: #{workspace_dir}"
        end
      end


      pipeline_class = Class.new(Pipeline) do
        agent_step(
          :custom_tool_step,
          tools: [
            :custom_tool_auto_initialized,
            :custom_tool_manually_initialized
          ],
          prompt: "hello",
          schema: -> {},
        )
      end

      responses = {
        "hello" => '{}'
      }

      tool_instance = custom_tool_auto_initialized.new(
        workspace_dir: "blah",
        env: { OTHER_ENV: "1"}
      )
      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session(
        chat_provider: ->(**params) {
          @dummy_chat = DummyChat.new(responses:, **params)
        },
        extra_tools: {
          custom_tool_auto_initialized:,
          custom_tool_manually_initialized: tool_instance,
        }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.done?, task.reload.error_message

      assert_equal 2, @dummy_chat.tools_received.count

      auto_initilaized_tool = @dummy_chat.tools_received.first
      assert auto_initilaized_tool.is_a?(custom_tool_auto_initialized)
      assert_equal("/tmp/example", auto_initilaized_tool.workspace_dir)

      # this env value was stored in a db, so stringified keys
      assert_equal({ "ENV_VALUE" => "1"}, auto_initilaized_tool.env)

      manually_initialized_tool = @dummy_chat.tools_received.last
      assert_equal("blah", manually_initialized_tool.workspace_dir)

      # this env was not stored in the db, so just as-is
      assert_equal({ OTHER_ENV: "1"}, manually_initialized_tool.env)
    end

  end
end
