# frozen_string_literal: true

require_relative "../test_helper"

module AgentC
  class BatchTest < UnitTest
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
      @session = Session.new(
        agent_db_path: DB_PATH,
        project: "test",
        run_id: "test-run",
        workspace_dir: "/tmp/test",
        logger: Logger.new(nil)
      )

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

      @batch = Batch.new(
        store: @store,
        workspace: @workspace,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class,
      )
    end

    def test_basics
      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      @batch.add_task(record)

      @batch.call

      record.reload
      assert_equal "assigned", record.attr_1
      assert_equal "assigned", record.attr_2
      assert_equal "assigned", record.attr_3
    end

    def test_multiple_records
      record1 = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      record2 = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      record3 = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")

      @batch.add_task(record1)
      @batch.add_task(record2)
      @batch.add_task(record3)

      @batch.call

      [record1, record2, record3].each do |record|
        record.reload
        assert_equal "assigned", record.attr_1
        assert_equal "assigned", record.attr_2
        assert_equal "assigned", record.attr_3
      end
    end

    def test_empty_batch
      @batch.call

      assert_equal 0, @store.task.count
    end

    def test_add_task_creates_task
      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")

      assert_equal 0, @store.task.count

      @batch.add_task(record)

      assert_equal 1, @store.task.count

      task = @store.task.first
      assert_equal record.id, task.record_id
      assert_equal "my_record", task.handler
      assert_equal "pending", task.status
    end

    def test_add_task_is_idempotent
      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")

      @batch.add_task(record)
      @batch.add_task(record)
      @batch.add_task(record)

      assert_equal 1, @store.task.count
    end

    def test_accessors
      assert_equal @store, @batch.store
      assert_equal [@workspace], @batch.workspaces
      assert_equal @session, @batch.session
    end

    def test_pipeline_has_access_to_task
      received_task = nil

      pipeline_class = Class.new(Pipeline) do
        step(:capture_task) do
          received_task = task
          record.update!(attr_1: "done")
        end
      end

      batch = Batch.new(
        store: @store,
        workspace: @workspace,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class
      )

      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      batch.add_task(record)
      batch.call

      refute_nil received_task
      assert_equal record.id, received_task.record_id
    end

    def test_pipeline_has_access_to_session
      received_session = nil

      pipeline_class = Class.new(Pipeline) do
        step(:capture_session) do
          received_session = session
          record.update!(attr_1: "done")
        end
      end

      batch = Batch.new(
        store: @store,
        workspace: @workspace,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class
      )

      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      batch.add_task(record)
      batch.call

      assert_equal @session, received_session
    end

    def test_pipeline_has_access_to_workspace
      received_workspace = nil

      pipeline_class = Class.new(Pipeline) do
        step(:capture_workspace) do
          received_workspace = workspace
          record.update!(attr_1: "done")
        end
      end

      batch = Batch.new(
        store: @store,
        workspace: @workspace,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class
      )

      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      batch.add_task(record)
      batch.call

      assert_equal @workspace, received_workspace
    end

    def test_pipeline_has_access_to_store
      received_store = nil

      pipeline_class = Class.new(Pipeline) do
        step(:capture_store) do
          received_store = store
          record.update!(attr_1: "done")
        end
      end

      batch = Batch.new(
        store: @store,
        workspace: @workspace,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class
      )

      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      batch.add_task(record)
      batch.call

      assert_equal @store, received_store
    end

    def test_pipeline_has_access_to_record
      received_record = nil

      pipeline_class = Class.new(Pipeline) do
        step(:capture_record) do
          received_record = record
          record.update!(attr_1: "done")
        end
      end

      batch = Batch.new(
        store: @store,
        workspace: @workspace,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class
      )

      record = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      batch.add_task(record)
      batch.call

      assert_equal record, received_record
    end

    def test_report_with_no_tasks
      report = @batch.report

      assert_equal "Total: 0\nSucceeded: 0\nPending: 0\nFailed: 0\nWorktrees: 1\nRun cost: $0.00\nProject total cost: $0.00\n", report
    end

    def test_report_with_succeeded_tasks
      record1 = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      record2 = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")

      @batch.add_task(record1)
      @batch.add_task(record2)
      @batch.call

      report = @batch.report

      # Check that the report contains expected sections
      assert_match(/^Total: 2$/, report)
      assert_match(/^Succeeded: 2$/, report)
      assert_match(/^Pending: 0$/, report)
      assert_match(/^Failed: 0$/, report)
      assert_match(/^Time: \d+ hrs, \d+ mins, \d+ secs$/, report)
      assert_match(/^Worktrees: 1$/, report)
      assert_match(/^Run cost: \$0\.00$/, report)
      assert_match(/^Project total cost: \$0\.00$/, report)
      assert_match(/^Cost per task: \$0\.00$/, report)
      assert_match(/^Minutes per task: \d+\.\d+$/, report)
    end

    def test_report_with_mixed_statuses
      # Create tasks with different statuses
      task1 = @store.task.create!(status: "done", handler: "my_record")
      task2 = @store.task.create!(status: "pending", handler: "my_record")
      task3 = @store.task.create!(status: "failed", handler: "my_record", error_message: "Error 1")

      report = @batch.report

      # Check that the report contains expected sections
      assert_match(/^Total: 3$/, report)
      assert_match(/^Succeeded: 1$/, report)
      assert_match(/^Pending: 1$/, report)
      assert_match(/^Failed: 1$/, report)
      assert_match(/^Time: \d+ hrs, \d+ mins, \d+ secs$/, report)
      assert_match(/^Worktrees: 1$/, report)
      assert_match(/^Run cost: \$0\.00$/, report)
      assert_match(/^Project total cost: \$0\.00$/, report)
      assert_match(/^Cost per task: \$0\.00$/, report)
      assert_match(/^Minutes per task: \d+\.\d+$/, report)
      assert_match(/First 1 failed task\(s\):/, report)
      assert_match(/- Error 1/, report)
    end

    def test_report_limits_failed_tasks_to_three
      # Create 5 failed tasks
      5.times do |i|
        @store.task.create!(
          status: "failed",
          handler: "my_record",
          error_message: "Error #{i + 1}"
        )
      end

      report = @batch.report

      # Check that the report contains expected sections
      assert_match(/^Total: 5$/, report)
      assert_match(/^Succeeded: 0$/, report)
      assert_match(/^Pending: 0$/, report)
      assert_match(/^Failed: 5$/, report)
      assert_match(/^Time: \d+ hrs, \d+ mins, \d+ secs$/, report)
      assert_match(/^Worktrees: 1$/, report)
      assert_match(/^Run cost: \$0\.00$/, report)
      assert_match(/^Project total cost: \$0\.00$/, report)
      assert_match(/^Cost per task: \$0\.00$/, report)
      assert_match(/^Minutes per task: \d+\.\d+$/, report)
      assert_match(/First 3 failed task\(s\):/, report)
      assert_match(/- Error 1/, report)
      assert_match(/- Error 2/, report)
      assert_match(/- Error 3/, report)
      refute_match(/- Error 4/, report)
      refute_match(/- Error 5/, report)
    end

    def test_worktrees_auto_created
      worktrees_dir = Dir.mktmpdir
      repo_dir = Dir.mktmpdir

      Utils::Shell.run!(
        <<~SH
          cd #{repo_dir} && \
            git init . && \
            mkdir subdir && \
            echo hello >> subdir/hello.txt && \
            git add --all && \
            git commit --no-gpg-sign --message 'commit'
        SH
      )

      revision = Utils::Shell.run!("cd #{repo_dir} && git rev-parse @").strip

      workspaces = []
      pipeline_class = Class.new(Pipeline) do
        step(:capture_store) do
          # simulate some work so that both pipelines don't end up
          # with same worktree... potentially flaky :(
          sleep 0.0005
          workspaces << workspace
        end
      end

      store = @store_class.new(dir: Dir.mktmpdir)

      batch = Batch.new(
        store: store,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class,
        repo: {
          dir: repo_dir,
          initial_revision: revision,
          working_subdir: "subdir",
          worktrees_root_dir: worktrees_dir,
          worktree_branch_prefix: "branch-prefix",
          worktree_envs: [
            { SOME_ENV_VAR: "0" },
            { SOME_ENV_VAR: "1" },
          ],
        }
      )

      record_1 = store.my_record.create!(
        attr_1: "initial",
        attr_2: "initial",
        attr_3: "initial"
      )
      record_2 = store.my_record.create!(
        attr_1: "initial",
        attr_2: "initial",
        attr_3: "initial"
      )
      batch.add_task(record_1)
      batch.add_task(record_2)

      batch.call

      assert_equal 2, workspaces.count

      worktree_0_dir = File.join(worktrees_dir, "branch-prefix-0/subdir")
      worktree_1_dir = File.join(worktrees_dir, "branch-prefix-1/subdir")

      assert File.exist?(File.join(worktree_0_dir, "hello.txt"))
      assert_equal(
        { dir: worktree_0_dir, env: { "SOME_ENV_VAR" => "0" }},
        workspaces.first.attributes.symbolize_keys.except(:id)
      )

      assert File.exist?(File.join(worktree_1_dir, "hello.txt"))
      assert_equal(
        { dir: worktree_1_dir, env: { "SOME_ENV_VAR" => "1" }},
        workspaces.last.attributes.symbolize_keys.except(:id)
      )
    end

    def test_report_shows_comprehensive_stats
      # Create multiple worktrees
      workspace1 = @store.workspace.create!(dir: "/tmp/workspace1", env: {})
      workspace2 = @store.workspace.create!(dir: "/tmp/workspace2", env: {})

      # Create tasks with known timestamps
      task1 = @store.task.create!(
        status: "done",
        handler: "my_record",
        workspace: workspace1,
        created_at: Time.now - 120, # 2 minutes ago
        updated_at: Time.now - 60    # 1 minute ago
      )
      task2 = @store.task.create!(
        status: "done",
        handler: "my_record",
        workspace: workspace2,
        created_at: Time.now - 120,
        updated_at: Time.now         # now
      )

      report = @batch.report

      # Should have 3 worktrees (initial workspace + 2 new ones)
      assert_match(/^Total: 2$/, report)
      assert_match(/^Worktrees: 3$/, report)
      assert_match(/^Time: 0 hrs, 2 mins, \d+ secs$/, report)

      # Minutes per task should account for parallelism
      # Total time: ~2 minutes, 3 worktrees, 2 tasks
      # Effective time per task: (2 minutes / 3 worktrees) / 2 tasks = ~0.33 minutes
      assert_match(/^Minutes per task: \d+\.\d+$/, report)

      # Cost per task now multiplies by worktree count
      # (0.00 * 3 worktrees) / 2 tasks = $0.00
      assert_match(/^Cost per task: \$0\.00$/, report)
    end

    def test_call_with_block_invoked_after_each_step
      called_with_tasks = []

      pipeline_class = Class.new(Pipeline) do
        step(:step_1) do
          record.update!(attr_1: "step_1_done")
        end

        step(:step_2) do
          record.update!(attr_2: "step_2_done")
        end

        step(:step_3) do
          record.update!(attr_3: "step_3_done")
        end
      end

      batch = Batch.new(
        store: @store,
        workspace: @workspace,
        session: @session,
        record_type: :my_record,
        pipeline: pipeline_class
      )

      record1 = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")
      record2 = @store.my_record.create!(attr_1: "initial", attr_2: "initial", attr_3: "initial")

      batch.add_task(record1)
      batch.add_task(record2)

      batch.call do |task|
        called_with_tasks << task
      end

      assert_equal 2, called_with_tasks.count

      assert_equal(called_with_tasks.sort_by(&:id), @store.task.all.order(:id))

      final_tasks = @store.task.all
      assert_equal 2, final_tasks.size
      final_tasks.each do |task|
        assert_equal "done", task.status
        assert_equal ["step_1", "step_2", "step_3"], task.completed_steps
      end

      # Verify records were updated correctly
      record1.reload
      assert_equal "step_1_done", record1.attr_1
      assert_equal "step_2_done", record1.attr_2
      assert_equal "step_3_done", record1.attr_3

      record2.reload
      assert_equal "step_1_done", record2.attr_1
      assert_equal "step_2_done", record2.attr_2
      assert_equal "step_3_done", record2.attr_3
    end
  end
end
