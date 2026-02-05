# frozen_string_literal: true

require_relative "../test_helper"
require "json-schema"

module AgentC
  class PipelineTest < UnitTest
    def setup
      @store_class = Class.new(VersionedStore::Base) do
        include AgentC::Store

        record(:my_record) do
          schema do |t|
            t.string(:attr_1)
            t.string(:attr_2)
            t.string(:attr_3)
          end

          has_many(
            :tasks,
            class_name: class_name(:task)
          )
        end

        record(:failure) do
          schema do |t|
            t.string(:name)
          end
        end
      end

      @store = @store_class.new(dir: Dir.mktmpdir)
      @workspace = @store.workspace.create!(
        dir: "/tmp/example",
        env: {}
      )
    end

    def test_pipeline_basics
      pipeline_class = Class.new(Pipeline) do
        step(:assign_attr_1) do
          record.update!(attr_1: "assigned")
        end

        step(:assign_attr_2) do
          record.update!(attr_2: "assigned")
        end

        step(:assign_attr_3) do
          record.update!(attr_3: "assigned")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert task.reload.done?
      assert_equal "assigned", record.reload.attr_1
      assert_equal "assigned", record.reload.attr_2
      assert_equal "assigned", record.reload.attr_3
    end

    def test_class_method_call
      pipeline_class = Class.new(Pipeline) do
        step(:step_1) do
          record.update!(attr_1: "done")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      result = pipeline_class.call(task:, session:)

      assert_instance_of pipeline_class, result
      assert task.reload.done?
    end

    def test_skips_completed_steps
      pipeline_class = Class.new(Pipeline) do
        step(:step_1) do
          record.update!(attr_1: "step_1")
        end

        step(:step_2) do
          record.update!(attr_2: "step_2")
        end

        step(:step_3) do
          record.update!(attr_3: "step_3")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      task.completed_steps << "step_1"
      session = test_session

      pipeline_class.call(task:, session:)

      assert_nil record.reload.attr_1
      assert_equal "step_2", record.attr_2
      assert_equal "step_3", record.attr_3
      assert task.reload.done?
    end

    def test_tracks_completed_steps
      pipeline_class = Class.new(Pipeline) do
        step(:step_1) do
          record.update!(attr_1: "done")
        end

        step(:step_2) do
          record.update!(attr_2: "done")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert_equal ["step_1", "step_2"], task.reload.completed_steps
    end

    def test_stops_on_task_failure
      pipeline_class = Class.new(Pipeline) do
        step(:step_1) do
          record.update!(attr_1: "done")
        end

        step(:step_2) do
          task.fail!("Something went wrong")
        end

        step(:step_3) do
          record.update!(attr_3: "should_not_run")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert_equal "done", record.reload.attr_1
      assert_nil record.attr_3
      assert task.reload.failed?
      assert_equal ["step_1"], task.completed_steps
    end

    def test_on_failure_callbacks
      pipeline_class = Class.new(Pipeline) do
        on_failure { store.failure.create! }

        step(:step_1) do
          task.fail!("Failed")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert_equal 1, @store.failure.count
      assert task.reload.failed?
    end

    def test_exception_handling
      pipeline_class = Class.new(Pipeline) do
        on_failure { store.failure.create! }

        step(:step_1) do
          record.update!(attr_1: "done")
        end

        step(:step_2) do
          raise StandardError, "Unexpected error"
        end

        step(:step_3) do
          record.update!(attr_3: "should_not_run")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert_equal 1, @store.failure.count
      assert task.reload.failed?
      assert_match(/Unexpected error/, task.error_message)
      assert_equal "done", record.reload.attr_1
      assert_nil record.attr_3
      assert_equal ["step_1"], task.completed_steps
    end

    def test_agent_step_with_success
      pipeline_class = Class.new(Pipeline) do
        agent_step(
          :process_with_agent,
          prompt: "Do something",
          schema: -> { string("attr_1") }
        )
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)

      dummy_chat = DummyChat.new(responses: {
        "Do something" => '{"status": "success", "attr_1": "from_agent"}'
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.done?
      assert_equal "from_agent", record.reload.attr_1
      assert_equal ["process_with_agent"], task.completed_steps
    end

    def test_agent_step_with_failure
      pipeline_class = Class.new(Pipeline) do
        agent_step(:process_with_agent, prompt: "Do something", schema: -> { })

        step(:step_2) do
          record.update!(attr_2: "should_not_run")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)

      dummy_chat = DummyChat.new(responses: {
        "Do something" => '{"status": "error", "message": "Agent failed"}'
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.failed?
      assert_match(/Agent failed/, task.error_message)
      assert_nil record.reload.attr_2
      assert_equal [], task.completed_steps
    end

    def test_workspace_helper
      pipeline_class = Class.new(Pipeline) do
        step(:check_workspace) do
          record.update!(attr_1: workspace.dir)
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert_equal "/tmp/example", record.reload.attr_1
    end

    def test_record_helper
      pipeline_class = Class.new(Pipeline) do
        step(:use_record) do
          record.update!(attr_1: "via_helper")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert_equal "via_helper", record.reload.attr_1
    end

    def test_multiple_on_failure_callbacks
      pipeline_class = Class.new(Pipeline) do
        on_failure { store.failure.create!(name: "first") }
        on_failure { store.failure.create!(name: "second") }

        step(:failing_step) do
          raise "Error"
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline_class.call(task:, session:)

      assert_equal ["first", "second"], @store.failure.all.map(&:name)
    end

    def test_agent_step_with_i18n
      pipeline_class = Class.new(Pipeline) do
        agent_step(
          :process_with_i18n,
          prompt_key: "test.prompt",
          cached_prompt_keys: ["test.cached_1", "test.cached_2"],
          schema: -> { string("attr_3") }
        )
      end

      record = @store.my_record.create!(attr_1: "value1", attr_2: "value2")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        test: {
          prompt: "Process with attr_1=%{attr_1} and attr_2=%{attr_2}",
          cached_1: "Cached instruction 1",
          cached_2: "Cached instruction 2"
        }
      })

      dummy_chat = DummyChat.new(responses: {
        "Process with attr_1=value1 and attr_2=value2" => '{"status": "success", "attr_3": "processed"}'
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.done?
      assert_equal "processed", record.reload.attr_3
      assert_equal ["process_with_i18n"], task.completed_steps
    end

    def test_agent_shorthand_i18n
      pipeline_class = Class.new(Pipeline) do
        agent_step(:process_with_i18n)
      end

      record = @store.my_record.create!(attr_1: "value1", attr_2: "value2")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        process_with_i18n: {
          tools: ["edit_file"],
          cached_prompts: [
            "Cached instruction 1",
            "Cached instruction 2",
          ],
          prompt: "Process with attr_1=%{attr_1} and attr_2=%{attr_2}",
          response_schema: {
            attr_3: {
              type: "string",
              description: "attr_3 description"
            },
          }
        }
      })

      dummy_chat = DummyChat.new(responses: {
        "Process with attr_1=value1 and attr_2=value2" => '{"status": "success", "attr_3": "processed"}'
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.done?, task.error_message
      assert_equal "processed", record.reload.attr_3
      assert_equal ["process_with_i18n"], task.completed_steps
    end

    def test_agent_step_tracks_chat_ids
      pipeline_class = Class.new(Pipeline) do
        agent_step(
          :first_step,
          prompt: "First prompt",
          schema: -> { string("attr_1") }
        )

        agent_step(
          :second_step,
          prompt: "Second prompt",
          schema: -> { string("attr_2") }
        )
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)

      first_chat = DummyChat.new(responses: {
        "First prompt" => '{"status": "success", "attr_1": "first"}'
      })

      second_chat = DummyChat.new(responses: {
        "Second prompt" => '{"status": "success", "attr_2": "second"}'
      })

      call_count = 0
      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) {
          call_count += 1
          call_count == 1 ? first_chat : second_chat
        }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.done?
      assert_equal 2, task.chat_ids.size
      assert_includes task.chat_ids, first_chat.id
      assert_includes task.chat_ids, second_chat.id
    end

    def test_agent_step_with_i18n_attributes
      store_class = Class.new(VersionedStore::Base) do
        include AgentC::Store

        record(:custom_record) do
          schema do |t|
            t.string(:attr_1)
            t.string(:attr_2)
            t.string(:attr_3)
          end

          has_many(
            :tasks,
            class_name: class_name(:task)
          )

          define_method(:i18n_attributes) do
            { foo: "bar" }
          end
        end
      end

      store = store_class.new(dir: Dir.mktmpdir)
      workspace = store.workspace.create!(
        dir: "/tmp/example",
        env: {}
      )

      pipeline_class = Class.new(Pipeline) do
        agent_step(
          :process_with_i18n,
          prompt_key: "test.prompt",
          cached_prompt_keys: ["test.cached_1", "test.cached_2"],
          schema: -> { string("attr_3") }
        )
      end

      record = store.custom_record.create!(attr_1: "value1", attr_2: "value2", attr_3: "initial")
      task = store.task.create!(record:, workspace:)

      I18n.backend.store_translations(:en, {
        test: {
          prompt: "Process with foo=%{foo}",
          cached_1: "Cached instruction 1",
          cached_2: "Cached instruction 2"
        }
      })

      dummy_chat = DummyChat.new(responses: {
        "Process with foo=bar" => '{"status": "success", "attr_3": "processed"}'
      })

      session = test_session(
        workspace_dir: workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.done?
      assert_equal "processed", record.reload.attr_3
      assert_equal ["process_with_i18n"], task.completed_steps
    end

    def test_agent_shorthand_i18n_with_i18n_attributes
      store_class = Class.new(VersionedStore::Base) do
        include AgentC::Store

        record(:custom_record) do
          schema do |t|
            t.string(:attr_1)
            t.string(:attr_2)
            t.string(:attr_3)
          end

          has_many(
            :tasks,
            class_name: class_name(:task)
          )

          define_method(:i18n_attributes) do
            { foo: "bar" }
          end
        end
      end

      store = store_class.new(dir: Dir.mktmpdir)
      workspace = store.workspace.create!(
        dir: "/tmp/example",
        env: {}
      )

      pipeline_class = Class.new(Pipeline) do
        agent_step(:process_with_i18n)
      end

      record = store.custom_record.create!(attr_1: "value1", attr_2: "value2", attr_3: "initial")
      task = store.task.create!(record:, workspace:)

      I18n.backend.store_translations(:en, {
        process_with_i18n: {
          tools: ["edit_file"],
          cached_prompts: [
            "Cached instruction 1",
            "Cached instruction 2",
          ],
          prompt: "Process with foo=%{foo}",
          response_schema: {
            attr_3: {
              type: "string",
              description: "attr_3 description"
            },
          }
        }
      })

      dummy_chat = DummyChat.new(responses: {
        "Process with foo=bar" => '{"status": "success", "attr_3": "processed"}'
      })

      session = test_session(
        workspace_dir: workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      pipeline_class.call(task:, session:)

      assert task.reload.done?, task.error_message
      assert_equal "processed", record.reload.attr_3
      assert_equal ["process_with_i18n"], task.completed_steps
    end
  end
end
