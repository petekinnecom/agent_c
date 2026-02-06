# Testing

AgentC provides testing utilities for writing tests without external dependencies:
- `TestHelpers::DummyChat` - Mock LLM responses without real API calls
- `TestHelpers::DummyGit` - Mock git operations without actual git commands
- `test_session` helper - Create test sessions with minimal configuration

The key benefit is that you use the actual `Session#prompt`, `Session#chat`, and `Pipeline` implementations, so your tests exercise real code paths without external dependencies.


## Testing Pipelines

Pipelines are the primary way to orchestrate multi-step agent workflows with persistent state. Testing pipelines involves setting up a store with your domain records, creating tasks, and using `DummyChat` to simulate LLM responses for `agent_step` calls.

### Basic Pipeline Test Setup

```ruby
require "test_helper"

class MyPipelineTest < Minitest::Test
  include AgentC::TestHelpers

  def setup
    # Create a store with your domain schema
    @store_class = Class.new(VersionedStore::Base) do
      include AgentC::Store

      record(:document) do
        schema do |t|
          t.string(:title)
          t.string(:summary)
          t.string(:category)
        end
      end
    end

    @store = @store_class.new(dir: Dir.mktmpdir)
    @workspace = @store.workspace.create!(
      dir: Dir.mktmpdir,
      env: {}
    )
  end

  def test_simple_pipeline
    # Define your pipeline
    pipeline_class = Class.new(Pipeline) do
      step(:set_title) do
        record.update!(title: "Document Title")
      end

      step(:set_category) do
        record.update!(category: "Important")
      end
    end

    # Create record and task
    document = @store.document.create!
    task = @store.task.create!(record: document, workspace: @workspace)
    session = test_session

    # Run the pipeline
    pipeline_class.call(task: task, session: session)

    # Verify results
    assert task.reload.done?
    assert_equal "Document Title", document.reload.title
    assert_equal "Important", document.category
  end
end
```

### Testing Agent Steps with Inline Definitions

The simplest way to test `agent_step` is to define them inline with the prompt and schema parameters. This avoids needing to set up I18n translations for tests.

**CRITICAL**: When using inline prompts with interpolation placeholders like `%{field_name}`, DummyChat receives the **literal prompt string** with placeholders intact, NOT the interpolated version. Match the exact string including `%{placeholders}` in your DummyChat responses.

```ruby
def test_agent_step_inline
  # Define pipeline with inline agent_step definitions
  pipeline_class = Class.new(AgentC::Pipeline) do
    agent_step(
      :summarize,
      prompt: "Summarize the document titled %{title}",
      schema: -> { string(:summary) }
    )

    agent_step(
      :categorize,
      prompt: "Categorize this document: %{summary}",
      schema: -> { string(:category) }
    )
  end

  document = @store.document.create!(title: "My Report")
  task = @store.task.create!(record: document, workspace: @workspace)

  # Match the LITERAL prompt strings with %{placeholders}, not interpolated values
  dummy_chat = DummyChat.new(responses: {
    "Summarize the document titled %{title}" =>
      '{" "summary": "A comprehensive report"}',
    "Categorize this document: %{summary}" =>
      '{" "category": "Research"}'
  })

  session = test_session(
    workspace_dir: @workspace.dir,
    chat_provider: ->(**params) { dummy_chat }
  )

  pipeline_class.call(task:, session:)

  document.reload
  assert_equal "A comprehensive report", document.summary
  assert_equal "Research", document.category
  assert task.reload.done?
end
```

### Testing Agent Steps with I18n Prompts

**CRITICAL DIFFERENCE**: When using I18n-based agent steps (like `agent_step(:my_step)` without inline prompt), the prompts ARE interpolated BEFORE being sent to DummyChat. Your responses must match the interpolated values, not the literal `%{placeholders}`.

```ruby
def test_i18n_agent_step
  # In prompts.yml:
  # my_step:
  #   prompt: "Process file %{file_name}"

  record = @store.document.create!(file_name: "report.pdf")
  task = @store.task.create!(record:, workspace: @workspace)

  # I18n interpolates BEFORE sending to DummyChat
  # DummyChat receives: "Process file report.pdf" (interpolated!)
  dummy_chat = DummyChat.new(responses: {
    "Process file report.pdf" => '{}',  # ✓ Correct
    "Process file %{file_name}" => '{}' # ✗ Wrong - won't match
  })

  session = test_session(
    workspace_dir: @workspace.dir,
    chat_provider: ->(**params) { dummy_chat }
  )

  MyPipeline.call(task:, session:)
end
```

When testing pipelines that use I18n-based `agent_step`, you need to:
1. Set up I18n translations with your prompts and schemas
2. Configure DummyChat responses that match the prompt text
3. Verify the agent step updates the record correctly

```ruby
def test_agent_step_with_i18n
  # Define pipeline with agent_step
  pipeline_class = Class.new(Pipeline) do
    agent_step(:summarize_document)
  end

  # Create record with initial data
  document = @store.document.create!(
    title: "My Document",
    category: "Technical"
  )
  task = @store.task.create!(record: document, workspace: @workspace)

  # Set up I18n translations for the agent step
  I18n.backend.store_translations(:en, {
    summarize_document: {
      tools: ["read_file"],
      cached_prompts: [
        "You are a document summarization assistant."
      ],
      prompt: "Summarize the document titled '%{title}' in category '%{category}'",
      response_schema: {
        summary: {
          type: "string",
          description: "The summary of the document"
        }
      }
    }
  })

  # Configure DummyChat with matching response
  dummy_chat = DummyChat.new(responses: {
    "Summarize the document titled 'My Document' in category 'Technical'" =>
      '{" "summary": "This is a technical document about programming."}'
  })

  # Create session with DummyChat
  session = test_session(
    workspace_dir: @workspace.dir,
    chat_provider: ->(**params) { dummy_chat }
  )

  # Run the pipeline
  pipeline_class.call(task: task, session: session)

  # Verify results
  assert task.reload.done?
  assert_equal "This is a technical document about programming.",
               document.reload.summary
  assert_equal ["summarize_document"], task.completed_steps
end
```

### Testing with Flexible Prompt Matching

For complex prompts or when using I18n with variable interpolation, use regex or proc matching:

```ruby
def test_agent_step_with_regex_matching
  pipeline_class = Class.new(Pipeline) do
    agent_step(:process_document)
  end

  document = @store.document.create!(title: "Test Doc")
  task = @store.task.create!(record: document, workspace: @workspace)

  I18n.backend.store_translations(:en, {
    process_document: {
      tools: ["read_file", "edit_file"],
      cached_prompts: ["Instructions..."],
      prompt: "Process document: %{title}",
      response_schema: {
        category: { type: "string", description: "Assigned category" }
      }
    }
  })

  # Use regex to match prompts flexibly
  dummy_chat = DummyChat.new(responses: {
    /Process document:/ => '{" "category": "Processed"}'
  })

  session = test_session(
    workspace_dir: @workspace.dir,
    chat_provider: ->(**params) { dummy_chat }
  )

  pipeline_class.call(task: task, session: session)

  assert_equal "Processed", document.reload.category
end
```

### Testing Error Handling in Pipelines

```ruby
def test_agent_step_failure
  pipeline_class = Class.new(Pipeline) do
    agent_step(:failing_step)

    step(:should_not_run) do
      record.update!(summary: "Should not execute")
    end
  end

  document = @store.document.create!
  task = @store.task.create!(record: document, workspace: @workspace)

  I18n.backend.store_translations(:en, {
    failing_step: {
      tools: [],
      cached_prompts: [],
      prompt: "This will fail",
      response_schema: { result: { type: "string", description: "Result" } }
    }
  })

  dummy_chat = DummyChat.new(responses: {
    "This will fail" => '{"unable_to_fulfill_request_error": "Processing failed"}'
  })

  session = test_session(
    workspace_dir: @workspace.dir,
    chat_provider: ->(**params) { dummy_chat }
  )

  pipeline_class.call(task: task, session: session)

  # Verify failure handling
  assert task.reload.failed?
  assert_match(/Processing failed/, task.error_message)
  assert_nil document.reload.summary
  assert_equal [], task.completed_steps
end
```

### Testing Pipeline with Multiple Agent Steps

```ruby
def test_multi_step_pipeline
  pipeline_class = Class.new(Pipeline) do
    agent_step(:extract_title)
    agent_step(:generate_summary)
    agent_step(:assign_category)
  end

  document = @store.document.create!
  task = @store.task.create!(record: document, workspace: @workspace)

  # Set up I18n for all steps
  I18n.backend.store_translations(:en, {
    extract_title: {
      tools: ["read_file"],
      cached_prompts: ["You extract titles from documents."],
      prompt: "Extract title",
      response_schema: {
        title: { type: "string", description: "Document title" }
      }
    },
    generate_summary: {
      tools: ["read_file"],
      cached_prompts: ["You summarize documents."],
      prompt: "Summarize document: %{title}",
      response_schema: {
        summary: { type: "string", description: "Summary" }
      }
    },
    assign_category: {
      tools: [],
      cached_prompts: ["You categorize documents."],
      prompt: "Categorize: %{title} - %{summary}",
      response_schema: {
        category: { type: "string", description: "Category" }
      }
    }
  })

  # Configure responses for each step
  dummy_chat = DummyChat.new(responses: {
    "Extract title" =>
      '{" "title": "Research Paper"}',
    "Summarize document: Research Paper" =>
      '{" "summary": "A study on testing"}',
    /Categorize: Research Paper - A study on testing/ =>
      '{" "category": "Research"}'
  })

  session = test_session(
    workspace_dir: @workspace.dir,
    chat_provider: ->(**params) { dummy_chat }
  )

  pipeline_class.call(task: task, session: session)

  # Verify all steps completed
  document.reload
  assert_equal "Research Paper", document.title
  assert_equal "A study on testing", document.summary
  assert_equal "Research", document.category
  assert task.reload.done?
  assert_equal ["extract_title", "generate_summary", "assign_category"],
               task.completed_steps
end
```

### Testing Pipeline Resumption

Pipelines track completed steps and can resume from where they left off:

```ruby
def test_pipeline_resumes_from_completed_steps
  pipeline_class = Class.new(Pipeline) do
    step(:step_1) do
      record.update!(title: "Step 1 Done")
    end

    step(:step_2) do
      record.update!(summary: "Step 2 Done")
    end

    step(:step_3) do
      record.update!(category: "Step 3 Done")
    end
  end

  document = @store.document.create!
  task = @store.task.create!(record: document, workspace: @workspace)

  # Mark step_1 as already completed
  task.completed_steps << "step_1"
  session = test_session

  pipeline_class.call(task: task, session: session)

  # step_1 was skipped, only step_2 and step_3 ran
  assert_nil document.reload.title
  assert_equal "Step 2 Done", document.summary
  assert_equal "Step 3 Done", document.category
  assert_equal ["step_1", "step_2", "step_3"], task.reload.completed_steps
end
```


## Testing Git Operations with DummyGit

When testing pipelines that perform git operations, use `DummyGit` to avoid actual git commands:

```ruby
require 'agent_c'
include AgentC::TestHelpers

def test_pipeline_with_git
  # Create a dummy git instance
  dummy_git = DummyGit.new(@workspace.dir)

  # Simulate that a file was created (has uncommitted changes)
  dummy_git.simulate_file_created!

  # Run pipeline with dummy git
  Pipeline.call(
    task: task,
    session: session,
    git: ->(_dir) { dummy_git }
  )

  # Verify git operations were called
  assert_equal 1, dummy_git.invocations.count
  commit = dummy_git.invocations.first
  assert_equal :commit_all, commit[:method]
  assert_match(/added file/, commit.dig(:args, 0))
end
```

### DummyGit API

- `initialize(workspace_dir)` - Create instance with working directory
- `uncommitted_changes?` - Returns false by default, true after `simulate_file_created!`
- `simulate_file_created!` - Makes `uncommitted_changes?` return true
- `invocations` - Array of all method calls with `{method:, args:, params:}` hashes
- Responds to any method via `method_missing`, recording invocations

## Basic Usage with session.prompt

```ruby
require 'agent_c'
include AgentC::TestHelpers

# Create a real session with DummyChat as the chat provider
session = Session.new(
  chat_provider: ->(**params) {
    DummyChat.new(
      responses: {
        "What is 2+2?" => '{" "answer": "4"}'
      },
      **params
    )
  }
)

# Use it just like a real session
result = session.prompt(
  prompt: "What is 2+2?",
  schema: -> { string(:answer) }
)

result.success? # => true
result.data["answer"] # => "4"
```

## Using session.chat with DummyChat

For testing multi-turn conversations, inject DummyChat directly as a record:

```ruby
session = Session.new()
dummy_chat = DummyChat.new(responses: {
  "Hello" => "Hi there!",
  "How are you?" => "I'm doing well!"
})

# Inject DummyChat as the record
chat = session.chat(tools: [], record: dummy_chat)

response1 = chat.ask("Hello")
response1.content # => "Hi there!"

response2 = chat.ask("How are you?")
response2.content # => "I'm doing well!"
```

## Response Mapping

TestHelpers::DummyChat accepts a hash mapping prompts to responses. Response values can be strings or callables (lambdas/procs) for simulating side effects. You can use:

### Exact String Matching

```ruby
session = Session.new(
  chat_provider: ->(**params) {
    DummyChat.new(
      responses: {
        "What is Ruby?" => '{" "answer": "A programming language"}'
      },
      **params
    )
  }
)
```

### Regex Matching

```ruby
session = Session.new(
  chat_provider: ->(**params) {
    DummyChat.new(
      responses: {
        /extract.*email/ => '{" "email": "user@example.com"}'
      },
      **params
    )
  }
)

# Matches any prompt containing "extract" followed by "email"
result = session.prompt(
  prompt: "Please extract the email from this text",
  schema: -> { string(:email) }
)
```

### Proc Matching

```ruby
session = Session.new(
  chat_provider: ->(**params) {
    DummyChat.new(
      responses: {
        ->(text) { text.include?("hello") } => '{" "greeting": "Hi!"}'
      },
      **params
    )
  }
)

# Matches any prompt containing "hello"
result = session.prompt(
  prompt: "Say hello to me",
  schema: -> { string(:greeting) }
)
```

### Callable Response Values

Response values can be callables (lambdas/procs) that are invoked when the prompt matches. This is useful for:
- Simulating side effects like file writes or API calls
- Returning dynamic values based on state
- Testing scenarios where the LLM interaction triggers other operations

```ruby
require 'tmpdir'

session = Session.new(
  chat_provider: ->(**params) {
    DummyChat.new(
      responses: {
        "Write file" => -> {
          File.write("/tmp/test.txt", "content")
          '{" "path": "/tmp/test.txt"}'
        }
      },
      **params
    )
  }
)

result = session.prompt(
  prompt: "Write file",
  schema: -> { string(:path) }
)

# The callable was invoked, file is written
assert File.exist?("/tmp/test.txt")
assert_equal "/tmp/test.txt", result.data["path"]
```

You can also use callables with stateful closures:

```ruby
call_count = 0

dummy_chat = DummyChat.new(responses: {
  "Count" => -> {
    call_count += 1
    "Called #{call_count} times"
  }
})

session = Session.new()
chat = session.chat(tools: [], record: dummy_chat)

chat.ask("Count") # => "Called 1 times"
chat.ask("Count") # => "Called 2 times"
```

## Success and Error Responses

TestHelpers::DummyChat supports both success and error responses:

### Success Response

```ruby
session = Session.new(
  chat_provider: ->(**params) {
    DummyChat.new(
      responses: {
        "Process data" => '{" "result": "processed"}'
      },
      **params
    )
  }
)

result = session.prompt(
  prompt: "Process data",
  schema: -> { string(:result) }
)

result.success? # => true
result.data["result"] # => "processed"
```

### Error Response

```ruby
session = Session.new(
  chat_provider: ->(**params) {
    DummyChat.new(
      responses: {
        "Impossible task" => '{"unable_to_fulfill_request_error": "Cannot complete"}'
      },
      **params
    )
  }
)

result = session.prompt(
  prompt: "Impossible task",
  schema: -> { string(:result) }
)

result.success? # => false
result.error_message # => "Cannot complete"
```

## Complete Test Example

```ruby
require "test_helper"

class MyFeatureTest < Minitest::Test
  include AgentC::TestHelpers

  def test_extract_email_from_text
    session = Session.new(
      chat_provider: ->(**params) {
        DummyChat.new(
          responses: {
            /extract.*email/ => '{" "email": "john@example.com"}'
          },
          **params
        )
      }
    )

    result = session.prompt(
      prompt: "Extract the email from: Contact John at john@example.com",
      schema: -> { string(:email) }
    )

    assert result.success?
    assert_equal "john@example.com", result.data["email"]
  end

  def test_handles_error_gracefully
    session = Session.new(
      chat_provider: ->(**params) {
        DummyChat.new(
          responses: {
            "Invalid input" => '{"unable_to_fulfill_request_error": "Input validation failed"}'
          },
          **params
        )
      }
    )

    result = session.prompt(
      prompt: "Invalid input",
      schema: -> { string(:result) }
    )

    refute result.success?
    assert_equal "Input validation failed", result.error_message
  end

  def test_multi_turn_conversation
    session = Session.new()
    dummy_chat = DummyChat.new(responses: {
      "Hello" => "Hi there!",
      /how.*you/ => "I'm doing well!"
    })

    chat = session.chat(tools: [], record: dummy_chat)

    assert_equal "Hi there!", chat.ask("Hello").content
    assert_equal "I'm doing well!", chat.ask("How are you?").content
  end
end
```

## Benefits

- **Fast**: No network calls or LLM processing
- **Predictable**: Same input always produces same output
- **Isolated**: Tests don't depend on external services
- **Cost-free**: No API charges during testing
- **Flexible**: Supports exact, regex, and proc matching
- **Real code paths**: Uses actual Session implementation

## Tips

1. **Understand the interpolation difference**:
   - **Inline agent_step**: DummyChat receives literal `%{placeholders}` - match `"Process %{name}"`
   - **I18n agent_step**: DummyChat receives interpolated values - match `"Process John"`

2. **Prefer inline agent_step definitions for tests**: Define agent_step with inline `prompt:` and `schema:` parameters instead of using I18n - it's simpler and keeps test logic self-contained

3. **Use regex for flexible matching**: When the exact prompt text may vary slightly, use regex patterns like `/Process file/` instead of exact strings

4. **Test both success and error cases**: Ensure your code handles both scenarios

5. **Keep responses realistic**: Use actual JSON structures your code expects

6. **One response map per test**: Makes tests easier to understand and maintain

7. **Inject via chat_provider for session.prompt**: Ensures DummyChat is used for all chat instances

8. **Inject via record for session.chat**: When you need fine-grained control over a specific chat instance

9. **Use callable responses for side effects**: When testing code that expects the LLM interaction to trigger file writes, API calls, or other state changes

10. **Use I18n for production agent_steps**: Store prompts in YAML files for production code, load them in tests with `I18n.load_path`

11. **Test pipeline resumption**: Verify that pipelines correctly skip already-completed steps
