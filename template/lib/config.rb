# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Config
  LOG_PATH = "./log/run.log"
  FileUtils.mkdir_p(File.dirname(LOG_PATH))

  LOGGER = Logger.new(LOG_PATH)

  PROJECT = "TemplateProject.v1"

  BATCH = {
    record_type: :summary,
    pipeline: Pipeline,

    store: {
      class: Store,
      config: {
        logger: LOGGER,
        dir: File.join(
          File.expand_path("../tmp", __dir__),
          PROJECT,
        )
      },
    },

    repo: {
      dir: File.expand_path("../../", __dir__),
      initial_revision: "main",
      working_subdir: "", # use the root-level of the repo
      worktrees_root_dir: "/tmp/example-worktrees",
      worktree_branch_prefix: "summary-examples",
      worktree_envs: [
        {
          SOME_ENV: "1",
        },
        {
          SOME_ENV: "2",
        },
      ],
    },

    session: {
      agent_db_path: File.expand_path("../../tmp/claude.sqlite", __dir__),
      logger: LOGGER,
      i18n_path: File.expand_path("prompts.yml", __dir__),
      project: PROJECT,
      ruby_llm: {
        bedrock_api_key: ENV.fetch("AWS_ACCESS_KEY_ID"),
        bedrock_secret_key: ENV.fetch("AWS_SECRET_ACCESS_KEY"),
        bedrock_session_token: ENV.fetch("AWS_SESSION_TOKEN"),
        bedrock_region: ENV.fetch("AWS_REGION", "us-west-2"),
        default_model: ENV.fetch("LLM_MODEL", "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
      }
    },
  }
end
