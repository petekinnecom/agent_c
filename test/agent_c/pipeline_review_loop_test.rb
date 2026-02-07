# frozen_string_literal: true

require_relative "../test_helper"
require "json-schema"

module AgentC
  class PipelineReviewLoopTest < UnitTest
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
      end

      @store = @store_class.new(dir: Dir.mktmpdir)
      @workspace = @store.workspace.create!(
        dir: "/tmp/example",
        env: {}
      )
    end

    def test_basics
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: [
            :implement_1,
            :implement_2,
          ],
          iterate: [
            :iterate_1,
            :iterate_2,
          ],
          review: [
            :review_1,
            :review_2,
          ],
        )
      end

      record = @store.my_record.create!(
        attr_1: "value_1",
        attr_2: "value_2"
      )
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1 %{attr_1}",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        implement_2: {
          prompt: "implement_2 %{attr_2}",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        iterate_1: {
          prompt: "iterate_1 %{attr_1} %{feedback}",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        iterate_2: {
          prompt: "iterate_2 %{attr_2} %{feedback}",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        review_1: { prompt: "review_1 %{attr_1}" },
        review_2: { prompt: "review_2 %{attr_2}" },
      })

      invocation_count = 0

      dummy_chat = DummyChat.new(responses: {
        /implement_1.*value_1/ => -> {
          invocation_count +=1
          {attr_1: "implement_#{invocation_count}"}.to_json
        },
        /implement_2.*value_2/ => -> {
          invocation_count += 1
          {attr_2: "implement_#{invocation_count}"}.to_json
        },
        /review_1.*implement_1/ => -> {
          invocation_count += 1
          {approved: false, feedback: "review_#{invocation_count}"}.to_json
        },
        /review_2.*implement_2/ => -> {
          invocation_count += 1
          {approved: false, feedback: "review_#{invocation_count}"}.to_json
        },
        /iterate_1.*review_3/m => -> {
          invocation_count += 1
          {attr_1: "iterate_#{invocation_count}"}.to_json
        },
        /iterate_2.*review_4/m => -> {
          invocation_count += 1
          {attr_2: "iterate_#{invocation_count}"}.to_json
        },
        /review_1.*iterate_5/m => -> {
          invocation_count += 1
          {approved: true, feedback: ""}.to_json
        },
        /review_2.*iterate_6/m => -> {
          invocation_count += 1
          {approved: true, feedback: ""}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      assert task.reload.done?, task.error_message
      assert_equal "iterate_5", record.reload.attr_1
      assert_equal "iterate_6", record.reload.attr_2
      assert_equal ["refactor"], task.completed_steps
    end

    def test_max_tries_exceeded
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 2,
          implement: :implement_1,
          review: :review_1
        )
      end

      record = @store.my_record.create!(attr_1: "value_1")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
      })

      invocation_count = 0

      # Review always fails
      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          invocation_count += 1
          {attr_1: "implement_#{invocation_count}"}.to_json
        },
        /review_1/ => -> {
          invocation_count += 1
          {approved: false, feedback: "needs work #{invocation_count}"}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      # Should complete the step even though review never passed
      # because max_tries was reached
      assert task.reload.done?, "Task should be done after max_tries"
      assert_equal ["refactor"], task.completed_steps
      # Should have run: implement (try 0), review (try 1), implement (try 1), review (try 2)
      assert_equal 4, invocation_count
    end

    def test_multiple_review_loops_in_pipeline
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :first_loop,
          max_tries: 2,
          implement: :implement_1,
          review: :review_1
        )

        agent_review_loop(
          :second_loop,
          max_tries: 2,
          implement: :implement_2,
          review: :review_2
        )
      end

      record = @store.my_record.create!(
        attr_1: "value_1",
        attr_2: "value_2"
      )
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        implement_2: {
          prompt: "implement_2",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
        review_2: { prompt: "review_2" },
      })

      first_loop_count = 0
      second_loop_count = 0

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          first_loop_count += 1
          {attr_1: "first_#{first_loop_count}"}.to_json
        },
        /review_1/ => -> {
          # Approve on first try
          {approved: true, feedback: ""}.to_json
        },
        /implement_2/ => -> {
          second_loop_count += 1
          {attr_2: "second_#{second_loop_count}"}.to_json
        },
        /review_2/ => -> {
          # Approve on first try
          {approved: true, feedback: ""}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      assert task.reload.done?
      assert_equal ["first_loop", "second_loop"], task.completed_steps
      assert_equal "first_1", record.reload.attr_1
      assert_equal "second_1", record.reload.attr_2
    end

    def test_implement_step_fails
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: :implement_1,
          review: :review_1
        )
      end

      record = @store.my_record.create!(attr_1: "value_1")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
      })

      # Implement returns invalid JSON (not matching schema)
      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          {wrong_field: "value"}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      # Task should be failed
      task.reload
      assert task.failed?, task.error_message
      assert task.error_message.include?("Failed to get valid response")
      assert_equal [], task.completed_steps
    end

    def test_iterate_step_fails
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: :implement_1,
          iterate: :iterate_1,
          review: :review_1
        )
      end

      record = @store.my_record.create!(attr_1: "value_1")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        iterate_1: {
          prompt: "iterate_1 %{feedback}",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
      })

      invocation_count = 0

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          invocation_count += 1
          {attr_1: "implement_#{invocation_count}"}.to_json
        },
        /review_1/ => -> {
          invocation_count += 1
          {approved: false, feedback: "needs work"}.to_json
        },
        /iterate_1/ => -> {
          # Return invalid response
          {wrong_field: "value"}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      # Task should be failed
      task.reload
      assert task.failed?, task.error_message
      assert task.error_message.include?("Failed to get valid response")
      assert_equal [], task.completed_steps
    end

    def test_review_step_fails_with_error
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: :implement_1,
          review: :review_1
        )
      end

      record = @store.my_record.create!(attr_1: "value_1")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
      })

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          {attr_1: "implement_1"}.to_json
        },
        /review_1/ => -> {
          # Return invalid response (missing required fields)
          {invalid: "response"}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      # Task should be failed
      task.reload
      assert task.failed?, task.error_message
      assert task.error_message.include?("Failed to get valid response")
      assert_equal [], task.completed_steps
    end

    def test_record_responds_to_add_review
      # Create a custom record class that implements add_review
      store_class = Class.new(VersionedStore::Base) do
        include AgentC::Store

        record(:my_record) do
          schema do |t|
            t.string(:attr_1)
            t.json(:reviews, default: [])
          end

          has_many(
            :tasks,
            class_name: class_name(:task)
          )

          def add_review(diff:, feedbacks:)
            self.reviews ||= []
            self.reviews << {diff: diff, feedbacks: feedbacks}
            save!
          end
        end
      end

      store = store_class.new(dir: Dir.mktmpdir)
      workspace = store.workspace.create!(
        dir: "/tmp/example",
        env: {}
      )

      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: :implement_1,
          review: :review_1
        )
      end

      record = store.my_record.create!(attr_1: "value_1")
      task = store.task.create!(record:, workspace:)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
      })

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          {attr_1: "implemented"}.to_json
        },
        /review_1/ => -> {
          {approved: true, feedback: ""}.to_json
        },
      })

      session = test_session(
        workspace_dir: workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      assert task.reload.done?
      # Verify add_review was called
      assert_equal 1, record.reload.reviews.length
      assert_equal [], record.reviews.first["feedbacks"]
    end

    def test_all_reviews_approve_first_try
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: [:implement_1, :implement_2],
          review: [:review_1, :review_2]
        )
      end

      record = @store.my_record.create!(
        attr_1: "value_1",
        attr_2: "value_2"
      )
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        implement_2: {
          prompt: "implement_2",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
        review_2: { prompt: "review_2" },
      })

      invocation_count = 0

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          invocation_count += 1
          {attr_1: "implement_#{invocation_count}"}.to_json
        },
        /implement_2/ => -> {
          invocation_count += 1
          {attr_2: "implement_#{invocation_count}"}.to_json
        },
        /review_1/ => -> {
          invocation_count += 1
          {approved: true, feedback: ""}.to_json
        },
        /review_2/ => -> {
          invocation_count += 1
          {approved: true, feedback: ""}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      assert task.reload.done?
      assert_equal ["refactor"], task.completed_steps
      # Should have run: implement_1, implement_2, review_1, review_2
      assert_equal 4, invocation_count
      assert_equal "implement_1", record.reload.attr_1
      assert_equal "implement_2", record.reload.attr_2
    end

    def test_second_implement_fails
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: [:implement_1, :implement_2],
          review: :review_1
        )
      end

      record = @store.my_record.create!(
        attr_1: "value_1",
        attr_2: "value_2"
      )
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        implement_2: {
          prompt: "implement_2",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
      })

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          {attr_1: "implemented"}.to_json
        },
        /implement_2/ => -> {
          # Return invalid response
          {wrong_field: "value"}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      # Task should be failed
      task.reload
      assert task.failed?, task.error_message
      assert task.error_message.include?("Failed to get valid response")
      assert_equal [], task.completed_steps
      # First implement should have succeeded
      assert_equal "implemented", record.reload.attr_1
      # Second implement should have failed, attr_2 should be unchanged
      assert_equal "value_2", record.attr_2
    end

    def test_second_iterate_fails
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: [:implement_1, :implement_2],
          iterate: [:iterate_1, :iterate_2],
          review: :review_1
        )
      end

      record = @store.my_record.create!(
        attr_1: "value_1",
        attr_2: "value_2"
      )
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        implement_2: {
          prompt: "implement_2",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        iterate_1: {
          prompt: "iterate_1 %{feedback}",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        iterate_2: {
          prompt: "iterate_2 %{feedback}",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
      })

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          {attr_1: "implement_1"}.to_json
        },
        /implement_2/ => -> {
          {attr_2: "implement_2"}.to_json
        },
        /review_1/ => -> {
          {approved: false, feedback: "needs work"}.to_json
        },
        /iterate_1/ => -> {
          {attr_1: "iterate_1"}.to_json
        },
        /iterate_2/ => -> {
          # Return invalid response
          {wrong_field: "value"}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      # Task should be failed
      task.reload
      assert task.failed?, task.error_message
      assert task.error_message.include?("Failed to get valid response")
      assert_equal [], task.completed_steps
    end

    def test_second_review_fails
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: [:implement_1, :implement_2],
          review: [:review_1, :review_2]
        )
      end

      record = @store.my_record.create!(
        attr_1: "value_1",
        attr_2: "value_2"
      )
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        implement_2: {
          prompt: "implement_2",
          response_schema: {
            attr_2: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
        review_2: { prompt: "review_2" },
      })

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          {attr_1: "implement_1"}.to_json
        },
        /implement_2/ => -> {
          {attr_2: "implement_2"}.to_json
        },
        /review_1/ => -> {
          {approved: true, feedback: ""}.to_json
        },
        /review_2/ => -> {
          # Return invalid response
          {invalid: "response"}.to_json
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      # Task should be failed
      task.reload
      assert task.failed?, task.error_message
      assert task.error_message.include?("Failed to get valid response")
      assert_equal [], task.completed_steps
    end

    def test_partial_review_approval
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: :implement_1,
          iterate: :iterate_1,
          review: [:review_1, :review_2]
        )
      end

      record = @store.my_record.create!(attr_1: "value_1")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        iterate_1: {
          prompt: "iterate_1 %{feedback}",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        review_1: { prompt: "review_1" },
        review_2: { prompt: "review_2" },
      })

      iteration = 0

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          iteration += 1
          {attr_1: "iteration_#{iteration}"}.to_json
        },
        /iterate_1/ => -> {
          iteration += 1
          {attr_1: "iteration_#{iteration}"}.to_json
        },
        /review_1/ => -> {
          # First review always approves
          {approved: true, feedback: ""}.to_json
        },
        /review_2/ => -> {
          # Second review rejects first time, approves second time
          if iteration == 1
            {approved: false, feedback: "needs more work"}.to_json
          else
            {approved: true, feedback: ""}.to_json
          end
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      assert task.reload.done?
      assert_equal ["refactor"], task.completed_steps
      assert_equal "iteration_2", record.reload.attr_1
    end

    def test_missing_implement_and_iterate
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          review: :review_1
        )
      end

      record = @store.my_record.create!(attr_1: "value_1")
      task = @store.task.create!(record:, workspace: @workspace)

      I18n.backend.store_translations(:en, {
        review_1: { prompt: "review_1" },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { DummyChat.new }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      git = ->(_dir) { dummy_git }

      # Pipeline.call catches ArgumentError and marks task as failed
      pipeline_class.call(task:, session:, git:)

      task.reload
      assert task.failed?, task.error_message
      assert_match(/must pass.*implement.*iterate/i, task.error_message)
    end

    def test_git_diff_called_per_review_iteration
      pipeline_class = Class.new(Pipeline) do
        agent_review_loop(
          :refactor,
          max_tries: 3,
          implement: :implement_1,
          iterate: :iterate_1,
          review: :review_1
        )
      end

      record = @store.my_record.create!(attr_1: "value_1")
      task = @store.task.create!(record:, workspace: @workspace)

      # Set up I18n translations
      I18n.backend.store_translations(:en, {
        implement_1: {
          prompt: "implement_1",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        iterate_1: {
          prompt: "iterate_1 %{feedback}",
          response_schema: {
            attr_1: { description: "" }
          }
        },
        review_1: { prompt: "review_1 %{diff}" },
      })

      iteration = 0

      dummy_chat = DummyChat.new(responses: {
        /implement_1/ => -> {
          iteration += 1
          {attr_1: "iteration_#{iteration}"}.to_json
        },
        /iterate_1/ => -> {
          iteration += 1
          {attr_1: "iteration_#{iteration}"}.to_json
        },
        /review_1.*diff_\d+/ => -> {
          # Approve on second iteration
          if iteration < 2
            {approved: false, feedback: "needs work"}.to_json
          else
            {approved: true, feedback: ""}.to_json
          end
        },
      })

      session = test_session(
        workspace_dir: @workspace.dir,
        chat_provider: ->(**params) { dummy_chat }
      )

      dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
      # Make git.diff return different values on each call
      def dummy_git.diff
        @diff_count ||= 0
        @diff_count += 1
        "diff_#{@diff_count}"
      end

      git = ->(_dir) { dummy_git }

      pipeline_class.call(task:, session:, git:)

      assert task.reload.done?
      assert_equal 2, dummy_git.instance_variable_get(:@diff_count)
    end
  end
end
