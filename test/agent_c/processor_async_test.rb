# frozen_string_literal: true

require_relative "../test_helper"

module AgentC
  class ProcessorAsyncTest < UnitTest
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
      @workspace_1 = @store.workspace.create!(
        dir: "/tmp/example",
        env: {}
      )
      @workspace_2 = @store.workspace.create!(
        dir: "/tmp/example2",
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

      context = Context.new(store: @store, session:, workspace: [@workspace_1, @workspace_2])
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

    def test_tasks_distributed_across_multiple_workspaces
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      session = test_session

      context = Context.new(store: @store, session:, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          pipeline_1: ->(task) { @pipeline_class.call(task:, session:) }
        }
      )

      task_1 = processor.add_task(record_1, :pipeline_1)
      task_2 = processor.add_task(record_2, :pipeline_1)

      assert_nil task_1.workspace_id
      assert_nil task_2.workspace_id

      processor.call

      task_1.reload
      task_2.reload

      assert task_1.done?
      assert task_2.done?
      refute_nil task_1.workspace_id
      refute_nil task_2.workspace_id
    end

    def test_tasks_with_pre_assigned_workspaces
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      session = test_session

      context = Context.new(store: @store, session:, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { @pipeline_class.call(task:, session:) }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      processor.call

      assert_equal @workspace_1.id, task_1.reload.workspace_id
      assert_equal @workspace_2.id, task_2.reload.workspace_id
      assert task_1.done?
      assert task_2.done?
    end

    def test_concurrent_execution_across_workspaces
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!

      execution_timestamps = {}
      mutex = Mutex.new

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) {
            start_time = Time.now
            sleep(0.1)
            mutex.synchronize do
              execution_timestamps[task.id] = { start: start_time, end: Time.now }
            end
            task.update!(status: :done)
          }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      processor.call

      # If tasks ran concurrently, they should overlap in time
      # If task_1 starts at 0 and ends at 0.1, and task_2 starts at 0 and ends at 0.1
      # then task_2.start should be before task_1.end
      task_1_times = execution_timestamps[task_1.id]
      task_2_times = execution_timestamps[task_2.id]

      # Verify both tasks completed
      assert task_1.reload.done?
      assert task_2.reload.done?

      # Verify overlap (concurrent execution)
      # If they ran sequentially, the second would start after the first ended
      # If concurrent, there should be time overlap
      assert task_2_times[:start] < task_1_times[:end]
      assert task_1_times[:start] < task_2_times[:end]
    end

    def test_exception_in_one_workspace_propagates_and_aborts_all
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) {
            if task.workspace_id == @workspace_1.id
              raise StandardError.new("workspace 1 failed")
            else
              task.update!(status: :done)
            end
          }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      # Exception should propagate and abort all workspaces
      error = assert_raises(StandardError) do
        processor.call
      end
      assert_equal "workspace 1 failed", error.message

      # Task 1 should still be pending due to exception
      assert task_1.reload.pending?
    end

    def test_task_pending_error_propagates_in_async_mode
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) {
            if task.workspace_id == @workspace_1.id
              # Handler completes but leaves task pending - will raise
            else
              task.update!(status: :done)
            end
          }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      # Task Pending error should propagate
      error = assert_raises(RuntimeError) do
        processor.call
      end
      assert_equal "Task Pending error", error.message

      # Task 1 should still be pending
      assert task_1.reload.pending?
    end

    def test_multiple_tasks_per_workspace_in_async_mode
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!
      record_4 = @store.my_record.create!
      session = test_session

      context = Context.new(store: @store, session:, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { @pipeline_class.call(task:, session:) }
        }
      )

      # Create tasks assigned to specific workspaces
      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_3 = @store.task.create!(
        record: record_3,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )
      task_4 = @store.task.create!(
        record: record_4,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      processor.call

      assert task_1.reload.done?
      assert task_2.reload.done?
      assert task_3.reload.done?
      assert task_4.reload.done?
    end

    def test_tasks_processed_in_order_within_each_workspace
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!

      execution_order = []
      mutex = Mutex.new

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) {
            mutex.synchronize do
              execution_order << [task.workspace_id, task.record.id]
            end
            task.update!(status: :done)
          }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      sleep 0.01
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      sleep 0.01
      task_3 = @store.task.create!(
        record: record_3,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      processor.call

      # Within workspace_1, tasks should be ordered by created_at
      workspace_1_order = execution_order.select { |ws_id, _| ws_id == @workspace_1.id }.map(&:last)
      assert_equal [record_1.id, record_2.id], workspace_1_order
    end

    def test_different_handlers_across_workspaces
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      session = test_session

      context = Context.new(store: @store, session:, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          pipeline_1: ->(task) { @pipeline_class.call(task:, session:) },
          pipeline_2: ->(task) { @pipeline_2.call(task:, session:) }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "pipeline_1",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "pipeline_2",
        workspace: @workspace_2,
        status: :pending
      )

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

    def test_async_with_many_workspaces
      @workspace_3 = @store.workspace.create!(dir: "/tmp/example3", env: {})
      @workspace_4 = @store.workspace.create!(dir: "/tmp/example4", env: {})

      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!
      record_4 = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2, @workspace_3, @workspace_4])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )
      task_3 = @store.task.create!(
        record: record_3,
        handler: "handler",
        workspace: @workspace_3,
        status: :pending
      )
      task_4 = @store.task.create!(
        record: record_4,
        handler: "handler",
        workspace: @workspace_4,
        status: :pending
      )

      processor.call

      assert task_1.reload.done?
      assert task_2.reload.done?
      assert task_3.reload.done?
      assert task_4.reload.done?
    end

    def test_callback_invoked_after_each_task_completes
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!

      completed_task_ids = []
      mutex = Mutex.new

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_3 = @store.task.create!(
        record: record_3,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      processor.call do
        mutex.synchronize do
          completed_task_ids << @store.task.where(status: :done).count
        end
      end

      # Callback should have been invoked 3 times (once after each task)
      assert_equal 3, completed_task_ids.size
      # Each invocation should see incrementing completed task counts
      assert_equal [1, 2, 3].sort, completed_task_ids.sort
    end

    def test_callback_can_trigger_abort
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      task_1 = @store.task.create!(
        record: record_1,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_2 = @store.task.create!(
        record: record_2,
        handler: "handler",
        workspace: @workspace_1,
        status: :pending
      )
      task_3 = @store.task.create!(
        record: record_3,
        handler: "handler",
        workspace: @workspace_2,
        status: :pending
      )

      completed_count = 0
      processor.call do
        completed_count += 1
        # Abort after first task completes
        processor.send(:abort!) if completed_count == 1
      end

      # Only one or two tasks should complete before abort takes effect
      # (depending on race conditions in async execution)
      completed = @store.task.where(status: :done).count
      assert completed <= 2, "Expected at most 2 tasks completed due to abort, got #{completed}"
      assert completed >= 1, "Expected at least 1 task completed before abort"
    end

    def test_callback_can_inspect_failure_counts
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!
      record_3 = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) {
            # First task fails, others succeed
            if task.record_id == record_1.id
              @store.failure.create!(name: "task_failed")
              task.update!(status: :failed)
            else
              task.update!(status: :done)
            end
          }
        }
      )

      task_1 = processor.add_task(record_1, :handler)
      task_2 = processor.add_task(record_2, :handler)
      task_3 = processor.add_task(record_3, :handler)

      failure_counts = []
      mutex = Mutex.new

      processor.call do
        mutex.synchronize do
          failure_counts << @store.failure.count
        end
      end

      # Should see failure count increase after first task
      assert_includes failure_counts, 1
    end

    def test_callback_without_block_works
      record_1 = @store.my_record.create!
      record_2 = @store.my_record.create!

      context = Context.new(store: @store, session: test_session, workspace: [@workspace_1, @workspace_2])
      processor = Processor.new(
        context:,
        handlers: {
          handler: ->(task) { task.update!(status: :done) }
        }
      )

      task_1 = processor.add_task(record_1, :handler)
      task_2 = processor.add_task(record_2, :handler)

      # Should work without a block
      processor.call

      assert task_1.reload.done?
      assert task_2.reload.done?
    end
  end
end
