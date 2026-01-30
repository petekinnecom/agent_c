# frozen_string_literal: true

require_relative "../test_helper"
require "json-schema"

module AgentC
  class StoreTest < Minitest::Test
    def setup
      db_dir = Dir.mktmpdir

      @my_store = Class.new(VersionedStore::Base) do
        include AgentC::Store

        record(:my_record) do
          schema do |t|
            t.string(:name)
          end

          has_many(
            :tasks,
            class_name: class_name(:task)
          )
        end
      end

      @store = @my_store.new(dir: db_dir)
    end

    def test_workspace_creation_with_defaults
      workspace = @store.workspace.create!(dir: "/tmp/example")

      assert_equal "/tmp/example", workspace.dir
      assert_equal [], workspace.env
    end

    def test_workspace_creation_with_env
      workspace = @store.workspace.create!(
        dir: "/tmp/example",
        env: { "FOO" => "bar" }
      )

      assert_equal "/tmp/example", workspace.dir
      assert_equal({ "FOO" => "bar" }, workspace.env)
    end

    def test_workspace_requires_dir
      error = assert_raises(ActiveRecord::NotNullViolation) do
        @store.workspace.create!(env: {})
      end

      assert_match(/dir/, error.message)
    end

    def test_task_creation_with_defaults
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "test_handler"
      )

      assert_equal "pending", task.status
      assert_equal [], task.completed_steps
      assert_equal "test_handler", task.handler
      assert_nil task.error_message
      assert_nil task.record_type
      assert_nil task.record_id
    end

    def test_task_pending_status_check
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "handler"
      )

      assert task.pending?
      refute task.done?
      refute task.failed?
    end

    def test_task_fail_method
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "handler"
      )

      task.fail!("Something went wrong")

      assert task.failed?
      refute task.pending?
      refute task.done?
      assert_equal "Something went wrong", task.error_message
      assert_equal "failed", task.status
    end

    def test_task_done_status
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "handler"
      )

      task.update!(status: "done")

      assert task.done?
      refute task.pending?
      refute task.failed?
    end

    def test_task_polymorphic_record_association
      workspace = @store.workspace.create!(dir: "/tmp/example")
      record = @store.my_record.create!(name: "my_record_1")
      task = @store.task.create!(
        workspace:,
        handler: "handler",
        record:
      )

      assert_equal record, task.record
      assert_equal "my_record", task.record_type
      assert_equal record.id, task.record_id
    end

    def test_task_without_record
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "handler"
      )

      assert_nil task.record
      assert_nil task.record_type
      assert_nil task.record_id
    end

    def test_task_completed_steps
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "handler",
        completed_steps: ["step1", "step2"]
      )

      assert_equal ["step1", "step2"], task.completed_steps
    end

    def test_workspace_association
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "handler"
      )

      assert_equal workspace, task.workspace
      assert_equal workspace.id, task.workspace_id
    end

    def test_task_has_timestamps
      workspace = @store.workspace.create!(dir: "/tmp/example")
      task = @store.task.create!(
        workspace:,
        handler: "handler"
      )

      refute_nil task.created_at
      refute_nil task.updated_at
    end
  end
end
