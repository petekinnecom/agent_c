# Pipeline Tips and Tricks

This document contains useful patterns and techniques for working with AgentC pipelines.

## Index

- [Custom I18n Attributes](#custom-i18n-attributes)
- [Rewinding to Previous Steps](#rewinding-to-previous-steps)

## Custom I18n Attributes

By default, when using i18n interpolation in your prompts, AgentC will use `record.attributes` to provide values for interpolation. However, you can customize this behavior by implementing an `i18n_attributes` method on your record.

### Use Case

This is useful when:
- You want to interpolate values that aren't stored as attributes on the record
- You need to compute or format values specifically for prompts
- You want to limit which attributes are exposed to i18n interpolation
- You need to provide different data than what's in the database

### Example

```ruby
class MyStore < VersionedStore::Base
  include AgentC::Store

  record(:my_record) do
    schema do |t|
      t.string(:file_path)
      t.text(:file_contents)
    end

    # Override the default i18n_attributes
    def i18n_attributes
      {
        file_name: File.basename(file_path),
        file_extension: File.extname(file_path),
        lines_count: file_contents&.lines&.count || 0
      }
    end
  end
end
```

Now in your prompts, you can interpolate these computed values:

```yaml
en:
  analyze_file:
    prompt: "Analyze %{file_name} which has %{lines_count} lines and is a %{file_extension} file"
```

### How It Works

When you use `agent_step` with i18n (either via `prompt_key` or the shorthand syntax), AgentC checks if your record responds to `i18n_attributes`. If it does, that method's return value is used for interpolation. Otherwise, it falls back to `record.attributes`.

This works with both explicit prompt keys:

```ruby
agent_step(
  :my_step,
  prompt_key: "my_step.prompt",
  cached_prompt_keys: ["my_step.cached"]
)
```

And with the shorthand syntax:

```ruby
agent_step(:my_step)
```

### Return Value

The `i18n_attributes` method should return a Hash with symbol or string keys. These keys will be used for interpolation in your i18n strings.

## Rewinding to Previous Steps

The `rewind_to!` method allows you to restart execution from a previously completed step. This is useful when you need to retry or re-execute steps based on runtime conditions.

### Use Case

This is useful when:
- An agent determines that a previous step needs to be re-executed
- You want to implement retry logic based on validation results
- You need to loop through steps until certain conditions are met
- A later step discovers that earlier work needs to be redone

### Basic Usage

```ruby
class Store < AgentC::Store
  record(:refactor) do
    schema do
      t.boolean(
        :review_passed,
        default: false
      )

      t.string(
        :review_feedback,
        default: "none"
      )
    end
  end
end

class MyPipeline < AgentC::Pipeline
  # prompt:
  #   Perform the refactor.
  #   Here is feedback from the reviewer (if any):
  #   %{review_feedback}
  agent_step(:perform_refactor)

  # capture the diff
  step(:capture_diff) do
    record.update!(diff: git.diff)
  end

  # prompt:
  #   Review this diff: %{diff}
  # schema:
  #  review_passed:
  #    type: boolean
  #  review_feedback:
  #    type: string
  agent_step(:review_refactor)

  step(:verify_output) do
    # if the review hasn't passed,
    # then review_feedback is now
    # present and will be passed
    # back in to refactor step above
    unless record.review_passed
      rewind_to!(:perform_refactor)
    end
  end
end
```

### How It Works

When you call `rewind_to!(step_name)`, the pipeline:
1. Validates that the specified step has already been completed
2. Validates that the step name appears only once in `completed_steps`
3. Removes the specified step and all subsequent steps from `completed_steps`
4. Continues execution from the rewound step

### Important Notes

**Infinite loops**: There's no automatic infinite loop detection. Use your record's state to count rewinds if you are concerned about a potential infinite loop.

**Must be called from within a step**: The `rewind_to!` method must be invoked from within a pipeline step during execution.

**Step must be completed**: You can only rewind to steps that have already been completed in the current pipeline run. Attempting to rewind to a step that hasn't been completed will raise an `ArgumentError`.

**Step must be unique**: If a step name appears multiple times in `completed_steps`, attempting to rewind to it will raise an `ArgumentError`. This prevents ambiguous rewind operations.

**State considerations**: When rewinding, be aware that any side effects from the original execution of the rewound steps will remain unless explicitly cleaned up. The pipeline doesn't automatically rollback database changes or other state modifications.

### Example: Retry Logic

```ruby
class ProcessWithRetry < AgentC::Pipeline
  step(:attempt_processing) do
    result = process_with_agent
    record.update!(
      attempt_count: record.attempt_count + 1,
      last_result: result
    )
  end

  step(:check_result) do
    if record.last_result.failed? && record.attempt_count < 3
      # Retry by going back to the processing step
      rewind_to!(:attempt_processing)
    elsif record.last_result.failed?
      task.fail!("Failed after 3 attempts")
    else
      record.update!(status: "completed")
    end
  end
end
```

### Error Handling

If you try to rewind to a step that hasn't been completed yet:

```ruby
step(:early_step) do
  rewind_to!(:later_step)  # ArgumentError: Cannot rewind to a step that's not been completed yet
end
```

If a step name appears multiple times in `completed_steps`:

```ruby
# This will raise an ArgumentError about non-distinct step names
rewind_to!(:duplicate_step)
