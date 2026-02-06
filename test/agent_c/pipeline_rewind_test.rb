# frozen_string_literal: true

require_relative "../test_helper"
require "json-schema"

module AgentC
  class PipelineRewindTest < UnitTest
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

    def test_rewind_to_reruns_specified_step
      counter = { attr_2_count: 0 }

      pipeline_class = Class.new(Pipeline) do
        define_method(:counter) { counter }

        step(:assign_attr_1) do
          record.update!(attr_1: "assigned")
        end

        step(:assign_attr_2) do
          counter[:attr_2_count] += 1
          record.update!(attr_2: "assigned_#{counter[:attr_2_count]}")
        end

        step(:assign_attr_3) do
          if counter[:attr_2_count] == 1
            rewind_to!(:assign_attr_2)
          end
          record.update!(attr_3: "assigned")
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline = pipeline_class.new(task:, session:)
      pipeline.call

      # attr_2 should have been run twice (once initially, once after rewind)
      assert_equal "assigned_2", record.reload.attr_2
      # attr_3 should be assigned (ran after the second execution of attr_2)
      assert_equal "assigned", record.reload.attr_3
      # completed_steps should have the final steps
      assert_equal ["assign_attr_1", "assign_attr_2", "assign_attr_3"], task.reload.completed_steps
    end

    def test_rewind_to_raises_when_step_not_yet_completed
      pipeline_class = Class.new(Pipeline) do
        step(:assign_attr_1) do
          rewind_to!(:assign_attr_2)
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

      pipeline = pipeline_class.new(task:, session:)
      # Don't call pipeline - no steps are completed

      pipeline.call
      assert_match(/not.*completed/i, task.error_message)
    end

    def test_rewind_to_raises_when_step_appears_multiple_times_in_completed_steps
      pipeline_class = Class.new(Pipeline) do
        step(:assign_attr_1) do
          record.update!(attr_1: "assigned")
        end

        step(:assign_attr_2) do
          record.update!(attr_2: "assigned")
        end

        step(:assign_attr_3) do
          # Manually add assign_attr_2 again to simulate it appearing twice
          task.completed_steps << "assign_attr_2"
          rewind_to!(:assign_attr_2)
        end
      end

      record = @store.my_record.create!
      task = @store.task.create!(record:, workspace: @workspace)
      session = test_session

      pipeline = pipeline_class.new(task:, session:)
      pipeline.call

      assert_match(/multiple times/i, task.error_message)
    end
  end
end
