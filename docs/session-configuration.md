# Session Configuration

Note: You probably want to make a `Batch`. See the [main README](../README.md)

This describes how to create a Session object if you just want to chat with Claude through AgentC.

## Overview

AgentC uses a session-based configuration approach that provides isolated configuration with no global state. Each session maintains its own configuration and RubyLLM context, making it ideal for:
- Testing (no configuration pollution between tests)
- Multiple concurrent configurations in the same process
- Better dependency injection and code organization

## Basic Session Configuration

```ruby
session = Session.new(
  # all chats with claude are saved to a sqlite db.
  # this is separate than your Store's db because
  # why throw anything away. Can be useful for
  # debugging why Claude did what it did
  agent_db_path: "/path/to/your/claude/db.sqlite",
  logger: Logger.new("/dev/null"), # probably use the same logger for everything...
  i18n_path: "/path/to/your/prompts.yml",

  # as you debug your pipeline, you'll probably run it
  # many times. We tag all Claude chat records with a
  # project so you can track costs.
  project: "SomeProject",

  # only available for Bedrock...
  ruby_llm: {
    bedrock_api_key: ENV.fetch("AWS_ACCESS_KEY_ID"),
    bedrock_secret_key: ENV.fetch("AWS_SECRET_ACCESS_KEY"),
    bedrock_session_token: ENV.fetch("AWS_SESSION_TOKEN"),
    bedrock_region: ENV.fetch("AWS_REGION", "us-west-2"),
    default_model: ENV.fetch("LLM_MODEL", "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
  }
)

# Create chats from the session
chat = session.chat
response = chat.ask("What is Ruby?")

# Or use the prompt method for one-off requests
result = session.prompt(
  prompt: "What is Ruby?",
  schema: -> { string(:answer) }
)
```

## Configuration Options

All session parameters are optional except where noted. If database-related features are needed, `agent_db_path` and `project` become required.

### agent_db_path

Path to the SQLite database file where all LLM interactions will be stored.

```ruby
session = Session.new(
  agent_db_path: 'tmp/db/agent.sqlite3'
)
```

The database is automatically created if it doesn't exist. All conversations, token usage, and costs are persisted here. Required if using database features (cost tracking, persistence).

### project (required with agent_db_path)

A string identifier for your project. Used to organize and filter cost reports.

```ruby
session = Session.new(
  agent_db_path: 'tmp/db/agent.sqlite3',
  project: 'my_project'
)
```

Required when `agent_db_path` is provided.

### workspace_dir

The working directory for file-based tools. Tools like `read_file`, `edit_file`, and `dir_glob` operate relative to this directory.

```ruby
session = Session.new(
  workspace_dir: Dir.pwd
)
```

Defaults to `Dir.pwd` if not specified.

### run_id

An optional identifier to group related queries. Useful for tracking multiple pipeline runs or sessions.

```ruby
session = Session.new(
  run_id: Time.now.to_i
)
```

Auto-generated if not provided when `agent_db_path` is configured.

### logger

Custom logger for debugging:

```ruby
session = Session.new(
  logger: Logger.new($stdout)
)
```

### i18n_path

Path to custom I18n translations file for prompts:

```ruby
session = Session.new(
  i18n_path: 'config/locales/prompts.yml'
)
```

This is particularly useful when using `agent_step` in Pipeline definitions, where prompts and schemas can be loaded from i18n YAML files.

### max_spend_project

Maximum project cost threshold in dollars. Raises `AgentC::Errors::AbortCostExceeded` when exceeded:

```ruby
session = Session.new(
  agent_db_path: 'tmp/db/agent.sqlite3',
  project: 'my_project',
  max_spend_project: 10.0  # Abort if project costs exceed $10
)
```

### max_spend_run

Maximum run cost threshold in dollars. Raises `AgentC::Errors::AbortCostExceeded` when exceeded:

```ruby
session = Session.new(
  agent_db_path: 'tmp/db/agent.sqlite3',
  project: 'my_project',
  run_id: 'run_123',
  max_spend_run: 5.0  # Abort if this run costs exceed $5
)
```

### ruby_llm

RubyLLM configuration hash. Each session has its own isolated RubyLLM context:

```ruby
session = Session.new(
  ruby_llm: {
    bedrock_api_key: ENV['AWS_ACCESS_KEY_ID'],
    bedrock_secret_key: ENV['AWS_SECRET_ACCESS_KEY'],
    bedrock_region: 'us-west-2',
    default_model: 'us.anthropic.claude-sonnet-4-5-20250929-v1:0'
  }
)
```

Available RubyLLM options:
- `bedrock_api_key` - AWS access key
- `bedrock_secret_key` - AWS secret key
- `bedrock_session_token` - Optional AWS session token
- `bedrock_region` - AWS region (e.g., 'us-west-2')
- `default_model` - Model ID to use

### extra_tools

A hash mapping tool names (symbols) to custom tool classes or instances. This allows you to add custom tools beyond the built-in AgentC tools.

```ruby
session = Session.new(
  extra_tools: {
    my_tool: MyCustomTool,           # Class will be initialized
    another_tool: MyOtherTool.new    # Instance used directly
  }
)
```

When a tool class is provided, AgentC will instantiate it with `workspace_dir:` and `env:` keyword arguments:

```ruby
# AgentC will call:
# MyCustomTool.new(workspace_dir: session.workspace_dir, env: session.env)
```

When a tool instance is provided, it will be used as-is without initialization.

Custom tools must implement the tool interface expected by RubyLLM. See the [Custom Tools documentation](custom-tools.md) for details on implementing custom tools.

## Complete Example

```ruby
require 'agent_c'
require 'logger'

# Create a fully configured session
session = Session.new(
  # Database and project
  agent_db_path: 'tmp/db/agent.sqlite3',
  project: 'document_processor',
  run_id: Time.now.to_i,

  # Working directory and i18n
  workspace_dir: Dir.pwd,
  i18n_path: 'config/locales/agent_prompts.yml',

  # Logging
  logger: Logger.new($stdout, level: Logger::INFO),

  # Cost controls
  max_spend_project: 100.0,
  max_spend_run: 10.0,

  # RubyLLM configuration
  ruby_llm: {
    bedrock_api_key: ENV['AWS_ACCESS_KEY_ID'],
    bedrock_secret_key: ENV['AWS_SECRET_ACCESS_KEY'],
    bedrock_region: 'us-west-2',
    default_model: 'us.anthropic.claude-sonnet-4-5-20250929-v1:0'
  },

  # Custom tools (optional)
  extra_tools: {
    custom_search: MySearchTool,
    api_client: MyApiClient.new(api_key: ENV['API_KEY'])
  }
)

# Create chats from the session
chat = session.chat(tools: [:read_file, :edit_file])
response = chat.ask("What is Ruby?")

# Or use the prompt method for one-off requests
result = session.prompt(
  prompt: "Summarize this file",
  schema: -> { string(:summary) },
  tools: [:read_file]
)
```

## Environment-Specific Configuration

```ruby
session = Session.new(
  agent_db_path: ENV['RACK_ENV'] == 'production' ?
    '/var/db/agent_production.sqlite3' :
    'tmp/db/agent_development.sqlite3',
  project: ENV['PROJECT_NAME'] || 'default_project',
  workspace_dir: Dir.pwd,
  logger: Logger.new($stdout, level: ENV['LOG_LEVEL'] || 'INFO'),
  ruby_llm: {
    bedrock_region: ENV['AWS_REGION'] || 'us-west-2',
    default_model: ENV['LLM_MODEL'] || 'us.anthropic.claude-sonnet-4-5-20250929-v1:0'
  }
)
```

## AWS Credentials

AgentC uses AWS Bedrock for LLM access. Ensure your AWS credentials are configured via:

- Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`)
- AWS credentials file (`~/.aws/credentials`)
- IAM role (when running on EC2/ECS)

No additional configuration is needed in AgentC for AWS credentials.
