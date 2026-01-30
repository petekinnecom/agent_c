# Custom Tools

If you are using a Batch, these tools are available and will be automatically configured for the correct directories/environment variables.

## Available tools

AgentC comes with several built-in tools that the LLM can use to interact with your codebase:

- `dir_glob` - List files matching patterns
- `read_file` - Read file contents
- `edit_file` - Make changes to files
- `file_metadata` - Get file information
- `grep` - Search within files
- `run_rails_test` - Execute Rails tests

# Using with sessions directly

This section is only relevant if you are not using a Batch.

## Using Tools

Tools are specified when creating a chat or using session.prompt:

```ruby
session = AgentC::Session.new(
  agent_db_path: 'tmp/db/agent.sqlite3',
  project: 'my_project'
)

# Chat with specific tools
chat = session.chat(tools: [:read_file, :grep])
response = chat.ask("What files contain the User model?")

# Or use session.prompt with tools
result = session.prompt(
  prompt: "Summarize the README",
  tools: [:read_file],
  tool_args: { working_dir: '/path/to/project' },
  schema: -> { string(:summary) }
)
```

## Tool Examples

### dir_glob

List files matching glob patterns:

```ruby
chat = session.chat(tools: [:dir_glob])
response = chat.ask("Show me all Ruby files in the lib directory")
```

### read_file

Read the contents of a file:

```ruby
chat = session.chat(tools: [:read_file])
response = chat.ask("What does lib/agent_c/chat.rb do?")
```

### edit_file

Make changes to files:

```ruby
chat = session.chat(tools: [:edit_file])
response = chat.ask("Add a method called 'foo' to lib/agent_c/chat.rb")
```

### grep

Search for patterns within files:

```ruby
chat = session.chat(tools: [:grep])
response = chat.ask("Find all calls to the 'process' method in the codebase")
```

### run_rails_test

Execute Rails tests:

```ruby
chat = session.chat(tools: [:run_rails_test])
response = chat.ask("Run the tests in test/models/user_test.rb")
```

## Tool Resolution with Pipelines

When using tools in Pipeline agent_steps, tools are automatically resolved to the workspace's working directory:

```ruby
class MyPipeline < AgentC::Pipeline
  agent_step(
    :analyze_code,
    tools: [:read_file, :grep]
  )
end
```

The tools will operate in the context of `workspace.dir` for that pipeline execution.
