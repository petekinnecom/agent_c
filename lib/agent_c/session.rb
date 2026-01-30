# frozen_string_literal: true

require "fileutils"

module AgentC
  class Session
    Configuration = Data.define(
      :agent_db_path,
      :logger,
      :i18n_path,
      :workspace_dir,
      :project,
      :run_id,
      :max_spend_project,
      :max_spend_run
    )

    attr_reader :logger

    def initialize(
      agent_db_path:,
      project:,
      logger: Logger.new("/dev/null"),
      workspace_dir: Dir.pwd,
      run_id: Time.now.to_i,
      i18n_path: nil,
      max_spend_project: nil,
      max_spend_run: nil,
      ruby_llm: {},
      chat_provider: ->(**params) { create_chat(**params) }
    )
      @agent_db_path = agent_db_path
      @project = project
      @logger = logger
      @workspace_dir = workspace_dir
      @run_id = run_id
      @i18n_path = i18n_path
      @max_spend_project = max_spend_project
      @max_spend_run = max_spend_run
      @ruby_llm = ruby_llm
      @chat_provider = chat_provider

      unless agent_db_path.match(/.sqlite3?$/)
        raise ArgumentError, "agent_db_path must end with '.sqlite3' or '.sqlite'"
      end

      # Load i18n path if provided
      if i18n_path
        I18n.load_path << i18n_path
      end
    end

    def chat(
      tools: Tools.all,
      cached_prompts: [],
      working_dir: nil,
      record: nil
    )
      @chat_provider.call(
        tools: tools,
        cached_prompts: cached_prompts,
        working_dir: working_dir || config.workspace_dir,
        record: record,
        session: self
      )
    end

    def prompt(
      tool_args: {},
      tools: Tools::NAMES.keys,
      cached_prompt: [],
      prompt:,
      schema:,
      on_chat_created: ->(*) {}
    )
      working_dir = tool_args[:working_dir] || config.workspace_dir
      # Merge working_dir into tool_args for Tools.resolve
      resolved_tool_args = tool_args.merge(working_dir: working_dir)

      chat_instance = chat(
        tools: tools.map { Tools.resolve(_1, **resolved_tool_args) },
        cached_prompts: cached_prompt,
        working_dir: working_dir
      )
      on_chat_created.call(chat_instance.id)

      message = Array(prompt).join("\n")

      begin
        result = chat_instance.get(message, schema: Schema.result(&schema))

        Agent::ChatResponse.new(
          chat_id: chat_instance.id,
          raw_response: result,
        )
      rescue => e
        Agent::ChatResponse.new(
          chat_id: chat_instance.id,
          raw_response: {
            "status" => "error",
            "message" => ["#{e.class.name}:#{e.message}", e.backtrace].join("\n")
          },
        )
      end
    end

    def config
      @config ||= Configuration.new(
        agent_db_path: @agent_db_path,
        logger: @logger,
        i18n_path: @i18n_path,
        workspace_dir: @workspace_dir,
        project: @project,
        run_id: @run_id,
        max_spend_project: @max_spend_project,
        max_spend_run: @max_spend_run,
      )
    end

    def ruby_llm_context
      @ruby_llm_context ||= RubyLLM.context do |ctx_config|
        @ruby_llm.each do |key, value|
          ctx_config.public_send("#{key}=", value)
        end
        ctx_config.use_new_acts_as = true
      end
    end

    def agent_store
      @agent_store ||= Db::Store.new(
        path: @agent_db_path,
        logger: @logger,
        versioned: false
      )
    end

    def cost
      Costs::Data.calculate(
        agent_store: agent_store,
        project: config.project,
        run_id: config.run_id
      )
    end

    private

    def create_chat(**params)
      real_record = params[:record] || (
        Agent::Chats::AnthropicBedrock.create(
          project: config.project,
          run_id: config.run_id,
          prompts: params.fetch(:cached_prompts, []),
          agent_store:,
          ruby_llm_context:
        )
      )

      real_record.on_end_message do |message|
        check_abort_cost
      end

      Agent::Chat.new(
        **params.except(:record),
        record: real_record
      )
    end

    def check_abort_cost
      return unless config.max_spend_project || config.max_spend_run

      if config.max_spend_project && cost.project >= config.max_spend_project
        raise Errors::AbortCostExceeded.new(
          cost_type: "project",
          current_cost: cost.project,
          threshold: config.max_spend_project
        )
      end

      if config.max_spend_run && cost.run >= config.max_spend_run
        raise Errors::AbortCostExceeded.new(
          cost_type: "run",
          current_cost: cost.run,
          threshold: config.max_spend_run
        )
      end
    end
  end
end
