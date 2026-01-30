# frozen_string_literal: true

require_relative "test_helper"

class PipelineTest < Minitest::Test
  include TestHelpers

  def setup
    @store = Store.new(
      logger: Logger.new(nil),
      dir: File.join(
        Dir.mktmpdir,
        "template_test"
      ),
    )

    @workspace = @store.workspace.create!(
      dir: Dir.mktmpdir,
      env: {}
    )

    # Load I18n translations from prompts.yml
    I18n.load_path << File.expand_path("../lib/prompts.yml", __dir__)
    I18n.backend.load_translations
  end

  def test_pipeline_end_to_end
    summary = @store.summary.create!(language: "Spanish")
    task = @store.task.create!(
      record: summary,
      workspace: @workspace
    )

    dummy_chat = AgentC::TestHelpers::DummyChat.new(responses: {
      /Find a random ruby file/ =>
        '{"status": "success", "input_path": "lib/pipeline.rb"}',
      /language: Spanish/ =>
        '{"status": "success", "summary_body": "Este archivo define un pipeline que resume archivos de Ruby"}',
      /---BEGIN-SUMMARY---/ =>
        '{"status": "success", "summary_path": "resumen_spanish.md"}'
    })

    # Setup dummy git to avoid actual git operations
    dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
    dummy_git.simulate_file_created!

    session = test_session(
      workspace_dir: @workspace.dir,
      chat_provider: ->(**params) { dummy_chat }
    )

    Pipeline.call(task:, session:, git: ->(_dir) { dummy_git })

    summary.reload
    assert_equal "lib/pipeline.rb", summary.input_path
    assert_equal "Este archivo define un pipeline que resume archivos de Ruby", summary.summary_body
    assert_equal "resumen_spanish.md", summary.summary_path
    assert task.reload.done?
    assert_equal ["pick_a_random_file", "summarize_the_file", "write_summary_to_disk", "finalize"],
                 task.completed_steps
  end

  def test_pipeline_with_different_languages
    summary = @store.summary.create!(language: "French")
    task = @store.task.create!(
      record: summary,
      workspace: @workspace
    )

    dummy_chat = AgentC::TestHelpers::DummyChat.new(responses: {
      /Find a random ruby file/ =>
        '{"status": "success", "input_path": "lib/store.rb"}',
      /language: French/ =>
        '{"status": "success", "summary_body": "Ce fichier définit le schéma de données pour les résumés"}',
      /---BEGIN-SUMMARY---/ =>
        '{"status": "success", "summary_path": "resume_french.md"}'
    })

    dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
    dummy_git.simulate_file_created!

    session = test_session(
      workspace_dir: @workspace.dir,
      chat_provider: ->(**params) { dummy_chat }
    )

    Pipeline.call(task:, session:, git: ->(_dir) { dummy_git })

    summary.reload
    assert_equal "lib/store.rb", summary.input_path
    assert_equal "Ce fichier définit le schéma de données pour les résumés", summary.summary_body
    assert_equal "resume_french.md", summary.summary_path
    assert task.reload.done?
  end

  def test_pipeline_finalize_commits_when_file_created
    summary = @store.summary.create!(
      language: "English",
      input_path: "lib/pipeline.rb",
      summary_body: "This file defines a pipeline",
      summary_path: "summary.md"
    )
    task = @store.task.create!(
      record: summary,
      workspace: @workspace
    )

    # Mark all agent steps as completed
    task.update!(completed_steps: ["pick_a_random_file", "summarize_the_file", "write_summary_to_disk"])

    dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
    dummy_git.simulate_file_created!

    session = test_session(workspace_dir: @workspace.dir)

    Pipeline.call(task:, session:, git: ->(_dir) { dummy_git })

    assert task.reload.done?
    assert_equal 1, dummy_git.invocations.count
    commit = dummy_git.invocations.first
    assert_equal :commit_all, commit[:method]
    assert_match(/claude: added file: summary\.md/, commit.dig(:args, 0))
  end

  def test_pipeline_finalize_fails_when_no_file_created
    summary = @store.summary.create!(
      language: "English",
      input_path: "lib/pipeline.rb",
      summary_body: "This file defines a pipeline",
      summary_path: "summary.md"
    )
    task = @store.task.create!(
      record: summary,
      workspace: @workspace
    )

    # Mark all agent steps as completed
    task.update!(completed_steps: ["pick_a_random_file", "summarize_the_file", "write_summary_to_disk"])

    dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
    # Don't simulate file creation - no changes

    session = test_session(workspace_dir: @workspace.dir)

    Pipeline.call(task:, session:, git: ->(_dir) { dummy_git })

    assert task.reload.failed?
    assert_match(/didn't create a file/, task.error_message)
  end

  def test_pipeline_handles_agent_step_failure
    summary = @store.summary.create!(language: "English")
    task = @store.task.create!(
      record: summary,
      workspace: @workspace
    )

    dummy_chat = AgentC::TestHelpers::DummyChat.new(responses: {
      /Find a random ruby file/ =>
        '{"status": "error", "message": "No suitable files found in repository"}'
    })

    dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)

    session = test_session(
      workspace_dir: @workspace.dir,
      chat_provider: ->(**params) { dummy_chat }
    )

    Pipeline.call(task:, session:, git: ->(_dir) { dummy_git })

    assert task.reload.failed?
    assert_match(/No suitable files found/, task.error_message)
    assert_nil summary.reload.input_path
    assert_equal [], task.completed_steps
  end

  def test_pipeline_resumes_from_completed_steps
    summary = @store.summary.create!(
      language: "Japanese",
      input_path: "lib/config.rb",
      summary_body: "このファイルは設定を定義します"
    )
    task = @store.task.create!(
      record: summary,
      workspace: @workspace
    )

    # Mark first two steps as completed
    task.update!(completed_steps: ["pick_a_random_file", "summarize_the_file"])

    dummy_chat = AgentC::TestHelpers::DummyChat.new(responses: {
      /---BEGIN-SUMMARY---/ =>
        '{"status": "success", "summary_path": "config_summary_ja.md"}'
    })

    dummy_git = AgentC::TestHelpers::DummyGit.new(@workspace.dir)
    dummy_git.simulate_file_created!

    session = test_session(
      workspace_dir: @workspace.dir,
      chat_provider: ->(**params) { dummy_chat }
    )

    Pipeline.call(task:, session:, git: ->(_dir) { dummy_git })

    summary.reload
    # First two steps' data should still be there
    assert_equal "lib/config.rb", summary.input_path
    assert_equal "このファイルは設定を定義します", summary.summary_body
    # Only the last step's data should be updated
    assert_equal "config_summary_ja.md", summary.summary_path
    assert task.reload.done?
    assert_equal ["pick_a_random_file", "summarize_the_file", "write_summary_to_disk", "finalize"],
                 task.completed_steps
  end

  def dummy_chat_factory(responses)
    ->(**_kwargs) { AgentC::TestHelpers::DummyChat.new(responses: responses) }
  end
end
