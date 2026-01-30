# frozen_string_literal: true

require_relative "../test_helper"

module AgentC
  class ProcessorSyncTest < UnitTest
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

      @pipeline_class = Class.new(Pipeline) do
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

      @pipeline_2 = Class.new(Pipeline) do
        step(:assign_attr_1_differently) do
          record.update!(attr_1: "pipeline_2")
        end

        step(:assign_attr_2_differently) do
          record.update!(attr_2: "pipeline_2")
        end

        step(:assign_attr_3_differently) do
          record.update!(attr_3: "pipeline_2")
        end
      end

    end

    def test_processor_basics
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      session = test_session

      context = Context.new(store: @store, session:, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          pipeline_1: ->(task) { @pipeline_class.call(task:, session:) }
        }
      )

      task_1 = processor.add_task(record_1, :pipeline_1)
      task_2 = processor.add_task(record_2, :pipeline_1)

      processor.call
      assert task_1.reload.done?
      assert task_2.reload.done?
    end

    def test_processor_with_different_handlers_per_record
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      session = test_session

      context = Context.new(store: @store, session:, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          pipeline_1: ->(task) { @pipeline_class.call(task:, session:) },
          pipeline_2: ->(task) { @pipeline_2.call(task:, session:) }
        }
      )

      task_1 = processor.add_task(record_1, :pipeline_1)
      task_2 = processor.add_task(record_2, :pipeline_2)

      processor.call

      assert task_1.reload.done?
      assert task_2.reload.done?

      record_1.reload
      assert_equal "assigned", record_1.attr_1
      assert_equal "assigned", record_1.attr_2
      assert_equal "assigned", record_1.attr_3

      record_2.reload
      assert_equal "pipeline_2", record_2.attr_1
      assert_equal "pipeline_2", record_2.attr_2
      assert_equal "pipeline_2", record_2.attr_3
    end

    def test_add_task_with_invalid_handler
      record = @store.my_record.create!
      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: { valid_handler: ->(task) {} }
      )

      error = assert_raises(ArgumentError) do
        processor.add_task(record, :invalid_handler)
      end
      assert_equal "invalid handler", error.message
    end

    def test_add_task_is_idempotent
      record = @store.my_record.create!
      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: { handler: ->(task) {} }
      )

      task_1 = processor.add_task(record, :handler)
      task_2 = processor.add_task(record, :handler)

      assert_equal task_1.id, task_2.id
    end

    def test_call_synchronous_requires_exactly_one_workspace
      @store.workspace.delete_all
      context = Context.new(store: @store, session: test_session, workspace: [])
      processor = Processor.new(
        context:,
        handlers: {}
      )

      error = assert_raises(RuntimeError) do
        processor.call
      end
      assert_equal "must provide at least one workspace", error.message
    end

    def test_tasks_processed_in_created_at_order
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!

      execution_order = []
      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) {
            execution_order << task.record.id
            task.update!(status: :done)
          }
        }
      )

      task_1 = processor.add_task(record_1, :handler)
      task_2 = processor.add_task(record_2, :handler)
      task_3 = processor.add_task(record_3, :handler)

      processor.call

      assert_equal [record_1.id, record_2.id, record_3.id], execution_order
    end

    def test_task_without_workspace_gets_assigned_to_workspace
      record = @store.my_record.create!
      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      task = processor.add_task(record, :handler)
      assert_nil task.workspace_id

      processor.call

      assert_equal @workspace.id, task.reload.workspace_id
    end

    def test_task_with_workspace_keeps_its_workspace
      workspace_2 = @store.workspace.create!(dir: "/tmp/example2", env: {})
      record = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: workspace_2)
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      task = @store.task.create!(
        record: record,
        handler: "handler",
        workspace: workspace_2,
        status: :pending
      )

      @store.workspace.where.not(id: workspace_2.id).destroy_all

      processor.call

      assert_equal workspace_2.id, task.reload.workspace_id
    end

    def test_handler_raises_when_task_still_pending
      record = @store.my_record.create!
      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) {
            # Handler completes but task stays pending
          }
        }
      )

      task = processor.add_task(record, :handler)

      error = assert_raises(RuntimeError) do
        processor.call
      end
      assert_equal "Task Pending error", error.message
      assert task.reload.pending?
    end

    def test_handlers_accepts_string_and_symbol_keys
      record = @store.my_record.create!
      called = false

      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          string_key: ->(task) {
            called = true
            task.update!(status: :done)
          }
        }
      )

      processor.add_task(record, "string_key")
      processor.call

      assert called
    end

    def test_callback_invoked_after_each_task_in_sync_mode
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!

      completed_task_ids = []

      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      processor.add_task(record_1, :handler)
      processor.add_task(record_2, :handler)
      processor.add_task(record_3, :handler)

      processor.call do
        completed_task_ids << @store.task.where(status: :done).count
      end

      # Callback should have been invoked 3 times (once after each task)
      assert_equal 3, completed_task_ids.size
      # Each invocation should see incrementing completed task counts
      assert_equal [1, 2, 3], completed_task_ids
    end

    def test_callback_can_trigger_abort_in_sync_mode
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: @workspace)
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      processor.add_task(record_1, :handler)
      processor.add_task(record_2, :handler)
      processor.add_task(record_3, :handler)

      completed_count = 0
      processor.call do
        completed_count += 1
        # Abort after first task completes
        processor.send(:abort!) if completed_count == 1
      end

      # Only first task should complete
      assert_equal 1, @store.task.where(status: :done).count
      assert_equal 2, @store.task.where(status: :pending).count
    end
  end
end
