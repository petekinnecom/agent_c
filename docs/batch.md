# Batch

The `Batch` class is the primary interface for executing pipelines across multiple records. It manages task processing, workspace allocation, and provides cost reporting.

## Overview

A Batch processes multiple records through a Pipeline in either serial or parallel execution. When you call `batch.call`, it will process all added tasks and optionally yield each task after completion.

```ruby
batch = Batch.new(
  record_type: :summary,
  pipeline: MyPipeline,
  store: store_config,
  workspace: workspace_config,
  session: session_config
)

batch.add_task(record1)
batch.add_task(record2)

# Process all tasks and yield each one after completion
batch.call do |task|
  puts "Completed task #{task.id} with status: #{task.status}"
end
```

## Configuration

### Required Parameters

#### `record_type:` (Symbol)

The name of the record class defined in your Store that this batch will process.

```ruby
record_type: :summary
```

#### `pipeline:` (Class)

The Pipeline class that defines the steps to execute for each task.

```ruby
pipeline: MyPipeline
```

#### `store:` (Hash or Object)

Configuration for the VersionedStore. Can be either a hash with configuration or a store instance directly.

As a hash:
```ruby
store: {
  class: MyStore,
  config: {
    logger: Logger.new("/dev/null"),
    dir: "/path/to/store/database"
  }
}
```

As a store instance:
```ruby
store: MyStore.new(dir: "/path/to/store")
```

#### `session:` (Hash or Object)

Configuration for the AI session. Can be either a hash with configuration or a session instance.

As a hash:
```ruby
session: {
  agent_db_path: "/path/to/agent.db",
  logger: Logger.new("/dev/null"),
  i18n_path: "/path/to/prompts.yml",
  project: "MyProject",
  ruby_llm: {
    bedrock_api_key: ENV.fetch("AWS_ACCESS_KEY_ID"),
    bedrock_secret_key: ENV.fetch("AWS_SECRET_ACCESS_KEY"),
    bedrock_region: "us-west-2",
    default_model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
  }
}
```

### Workspace Configuration

You must provide **either** `workspace:` or `repo:`, but not both.

#### `workspace:` (Hash or Object)

A single workspace for serial task processing.

```ruby
workspace: {
  dir: "/path/to/workspace",
  env: {
    RAILS_ENV: "test"
  }
}
```

Or as an object:
```ruby
workspace: store.workspace.create!(dir: "/path", env: {})
```

#### `repo:` (Hash)

Configuration for parallel processing using git worktrees.

```ruby
repo: {
  dir: "/path/to/repo",
  initial_revision: "main",
  working_subdir: "./app",  # optional
  worktrees_root_dir: "/tmp/worktrees",
  worktree_branch_prefix: "batch-task",
  worktree_envs: [
    { WORKER_ID: "0" },
    { WORKER_ID: "1" }
  ]
}
```

The number of worktrees created equals the length of `worktree_envs`. Each worktree processes tasks in parallel.

### Optional Parameters

#### `git:` (Proc)

A lambda that creates Git objects. Defaults to `Utils::Git.new`.

```ruby
git: ->(dir) { MyGitWrapper.new(dir) }
```

## Methods

### `#call(&block)`

Processes all pending tasks. Optionally yields each task after it completes.

```ruby
# Process without callback
batch.call

# Process with callback after each task
batch.call do |task|
  puts "Task #{task.id} finished with status: #{task.status}"
  puts "Completed steps: #{task.completed_steps.inspect}"
end
```

The block is called after each task finishes, regardless of whether it succeeded or failed. This allows you to:
- Monitor progress in real-time
- Log task completion
- Trigger external notifications
- Update UI or progress bars

### `#add_task(record)`

Adds a record to be processed. This method is idempotent - adding the same record multiple times will only create one task.

```ruby
record = batch.store.summary.create!(language: "english")
batch.add_task(record)
batch.add_task(record)  # No-op, task already exists
```

### `#report`

Returns a summary report of task statuses and costs.

```ruby
puts batch.report
# =>
# Succeeded: 5
# Pending: 0
# Failed: 1
# Run cost: $2.34
# Project total cost: $45.67
#
# First 1 failed task(s):
# - ArgumentError: Cannot rewind to a step that's not been completed yet
```

### `#abort!`

Stops task processing. Useful for gracefully shutting down long-running batches.

```ruby
# Stop if any task fails
batch.call do |task|
  batch.abort! if task.failed?
end
```

```ruby
# In a signal handler
Signal.trap("INT") do
  batch.abort!
end

batch.call
```

### Accessors

#### `#store`

Returns the Store instance.

```ruby
batch.store.summary.all
```

#### `#workspaces`

Returns an array of workspace objects available to this batch.

```ruby
batch.workspaces.each do |workspace|
  puts workspace.dir
end
```

#### `#session`

Returns the Session instance.

```ruby
cost = batch.session.cost
```

## Pipeline Integration

Pipelines executed by Batch have access to several methods for defining workflow steps.

### `step(name, &block)`

Defines a custom step that executes Ruby code.

```ruby
class MyPipeline < AgentC::Pipeline
  step(:assign_data) do
    record.update!(attr_1: "value")
  end

  step(:commit_changes) do
    git.commit_all("claude: updated data")
  end
end
```

**Available in step blocks:**
- `record` - The ActiveRecord instance being processed
- `task` - The Task instance tracking this pipeline execution
- `store` - The Store instance
- `workspace` - The Workspace instance
- `session` - The Session instance
- `git` - A Git helper (if git was configured)

**Resumability:** If a pipeline is interrupted and rerun, already-completed steps are skipped. The pipeline continues from the first incomplete step.

### `agent_step(name, **params)`

Defines a step that calls Claude with tools and expects structured output.

#### Using i18n (prompts.yml)

```ruby
agent_step(:analyze_code)
```

In your `prompts.yml`:
```yaml
en:
  analyze_code:
    cached_prompts:
      - "You are analyzing Ruby code."
    prompt: "Analyze this file: %{file_path}"
    tools: [read_file, dir_glob]
    response_schema:
      summary:
        type: string
        description: "A summary of the code"
```

#### Inline configuration

```ruby
agent_step(
  :analyze_code,
  prompt: "Analyze this code",
  cached_prompt: ["You are a code analyzer"],
  tools: [:read_file, :grep],
  schema: -> {
    string("summary", description: "Code summary")
  }
)
```

#### Dynamic configuration with a block

```ruby
agent_step(:process) do
  {
    prompt: "Process #{record.name}",
    tools: [:read_file],
    schema: -> { string("result") }
  }
end
```

**Result handling:** Claude's response is automatically saved to the record. If the response contains `unable_to_fulfill_request_error`, the task is marked as failed.

### `rewind_to!(step_name)`

Rewinds the pipeline to re-execute a specific step. This removes all steps after the specified step from the completed list and jumps back to that step.

```ruby
class MyPipeline < AgentC::Pipeline
  step(:fetch_data) do
    record.update!(data: fetch_from_api)
  end

  step(:validate_data) do
    if record.data.nil?
      # Re-fetch the data
      rewind_to!(:fetch_data)
    end
  end

  step(:process_data) do
    # This only runs if validation passed
    record.update!(processed: true)
  end
end
```

**Constraints:**
- The target step must have already been completed
- The target step name must be unique in the completed steps list

**Use cases:**
- Retry failed operations
- Implement conditional branching
- Handle rate limiting by backing up and waiting

## Examples

### Basic batch processing

```ruby
pipeline_class = Class.new(AgentC::Pipeline) do
  step(:assign_attr_1) do
    record.update!(attr_1: "assigned")
  end

  step(:assign_attr_2) do
    record.update!(attr_2: "assigned")
  end
end

batch = Batch.new(
  store: store,
  workspace: workspace,
  session: session,
  record_type: :my_record,
  pipeline: pipeline_class
)

record = store.my_record.create!(attr_1: "initial")
batch.add_task(record)
batch.call

puts record.reload.attr_1  # => "assigned"
```

### Processing with callback

```ruby
batch.call do |task|
  if task.done?
    puts "✓ Task #{task.id} completed"
    puts "  Steps: #{task.completed_steps.join(', ')}"
  elsif task.failed?
    puts "✗ Task #{task.id} failed"
    puts "  Error: #{task.error_message}"
  end
end
```

### Parallel processing with worktrees

```ruby
batch = Batch.new(
  store: store,
  session: session,
  record_type: :my_record,
  pipeline: pipeline_class,
  repo: {
    dir: "/path/to/repo",
    initial_revision: "main",
    worktrees_root_dir: "/tmp/worktrees",
    worktree_branch_prefix: "task",
    worktree_envs: [
      { WORKER: "0" },
      { WORKER: "1" }
    ]
  }
)

10.times do |i|
  record = store.my_record.create!(name: "record-#{i}")
  batch.add_task(record)
end

# Tasks are processed across 2 worktrees in parallel
batch.call
```

### Using rewind_to! for retries

```ruby
pipeline_class = Class.new(AgentC::Pipeline) do
  step(:fetch) do
    counter[:attempts] ||= 0
    counter[:attempts] += 1
    record.update!(data: fetch_api)
  end

  step(:validate) do
    if record.data.nil? && counter[:attempts] < 3
      rewind_to!(:fetch)
    elsif record.data.nil?
      task.fail!("Failed after 3 attempts")
    end
  end

  step(:process) do
    record.update!(processed: true)
  end
end
```

### Agent step with dynamic tools

```ruby
pipeline_class = Class.new(AgentC::Pipeline) do
  agent_step(:analyze) do
    tools = [:read_file]
    tools << :run_rails_test if record.needs_testing?

    {
      prompt: "Analyze #{record.file_path}",
      tools: tools,
      schema: -> { string("result") }
    }
  end
end
```

## Error Handling

If a step raises an exception or Claude returns an error:
1. The task is marked as failed
2. The `on_failure` callbacks from the pipeline are executed
3. Processing continues with the next task

```ruby
class MyPipeline < AgentC::Pipeline
  step(:risky_operation) do
    # May raise an exception
  end

  on_failure do
    # Clean up
    git.reset_hard_all
  end
end
```

## Resuming After Failure

If your batch is interrupted (exception, SIGTERM, etc.), simply run it again. Already-completed tasks and already-completed steps within partially-completed tasks will be skipped.

```ruby
# First run - processes some tasks then crashes
batch.call

# Second run - resumes from where it left off
batch.call
```

## See Also

- [Main README](../README.md) - Complete setup and configuration
- [Pipeline Tips and Tricks](pipeline-tips-and-tricks.md) - Advanced pipeline patterns
- [Store Versioning](versioned-store.md) - Rollback and recovery
- [Cost Reporting](cost-reporting.md) - Track AI usage costs
