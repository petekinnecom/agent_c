# Pipeline Tips and Tricks

This document contains useful patterns and techniques for working with AgentC pipelines.

## Index

- [Custom I18n Attributes](#custom-i18n-attributes)
- [Rewinding to Previous Steps](#rewinding-to-previous-steps)
- [Agent Review Loop](#agent-review-loop)

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
```

## Agent Review Loop

The `agent_review_loop` method provides a declarative way to implement iterative review and refinement workflows. It automatically handles the loop logic where an agent implements a solution, reviewers provide feedback, and the agent iterates based on that feedback until the reviewers approve or a maximum number of tries is reached.

### Use Case

This is useful when:
- You need an agent to generate code, designs, or content that requires review
- Multiple reviewers need to evaluate the work from different perspectives
- The agent should iterate based on feedback until reviewers approve
- You want to capture review history for audit or debugging purposes
- You need to limit the number of iteration attempts

### Basic Example

```ruby
class RefactorPipeline < AgentC::Pipeline
  agent_review_loop(
    :refactor_code,
    max_tries: 5,
    implement: :initial_refactor,
    iterate: :improve_refactor,
    review: :code_review
  )
end
```

With i18n translations:

```yaml
en:
  initial_refactor:
    prompt: "Refactor the code to improve readability"
    response_schema:
      code:
        description: "The refactored code"

  improve_refactor:
    prompt: |
      The previous refactor received this feedback:
      %{feedback}

      Please improve the refactor based on this feedback.
    response_schema:
      code:
        description: "The improved refactored code"

  code_review:
    prompt: |
      Review this code change:
      %{diff}

      Is it ready to merge?
    response_schema:
      approved:
        type: boolean
        description: "Whether the code is approved"
      feedback:
        type: string
        description: "Feedback if not approved (empty if approved)"
```

### How It Works

The `agent_review_loop` executes in iterations:

1. **First iteration (try 0)**:
   - Runs all `implement` steps in order
   - If any implement step fails, the loop stops and marks the task as failed
   - Captures git diff of changes
   - Runs all `review` steps with the diff
   - Collects feedback from any reviewers who don't approve

2. **Subsequent iterations (try 1+)**:
   - Runs all `iterate` steps with accumulated feedback
   - If any iterate step fails, the loop stops and marks the task as failed
   - Captures git diff of changes
   - Runs all `review` steps with the new diff
   - Collects feedback from any reviewers who don't approve

3. **Loop continues until**:
   - All reviewers approve (feedback list is empty), OR
   - `max_tries` is reached, OR
   - Any step fails, OR
   - The task is marked as failed by other means

### Multiple Steps

You can specify multiple steps for implement, iterate, and review:

```ruby
agent_review_loop(
  :multi_file_refactor,
  max_tries: 5,
  implement: [
    :refactor_controller,
    :refactor_model,
    :refactor_view
  ],
  iterate: [
    :improve_controller,
    :improve_model,
    :improve_view
  ],
  review: [
    :code_quality_review,
    :security_review,
    :performance_review
  ]
)
```

Steps are executed in order. If any step fails, the loop stops immediately.

### Feedback Interpolation

The `iterate` steps automatically receive a `%{feedback}` interpolation variable containing all feedback from reviewers, joined with `"\n---\n"` as a separator:

```yaml
improve_refactor:
  prompt: |
    Previous feedback from reviewers:
    %{feedback}

    Please address all concerns.
```

### Review Schema

Your "review" I18n should **not** include any response schema. AgentC will
configure the schema for you.

Review steps must return a response with these fields:
- `approved` (boolean): Whether the work is approved
- `feedback` (string): Feedback message if not approved (can be empty string if approved)

If a review step fails to return valid data, the task is marked as failed.

### Optional: Recording Reviews

If your record implements an `add_review` method, it will be called after each review iteration with the diff and collected feedback:

```ruby
record(:my_record) do
  schema do |t|
    t.json(:reviews, default: [])
  end

  def add_review(diff:, feedbacks:)
    self.reviews ||= []
    self.reviews << {
      timestamp: Time.now.iso8601,
      diff: diff,
      feedbacks: feedbacks
    }
    save!
  end
end
```

This allows you to maintain a complete history of all review iterations.

### Default Iterate Behavior

If you don't specify `iterate`, it defaults to the same value as `implement`:

```ruby
# These are equivalent:
agent_review_loop(:refactor, implement: :refactor_code, review: :review)
agent_review_loop(:refactor, implement: :refactor_code, iterate: :refactor_code, review: :review)
```

This is useful when the same prompt can handle both initial implementation and iteration based on feedback.

### Important Notes

**Required parameters**: You must provide either `implement` or `iterate` (or both). Providing only `review` will raise an `ArgumentError`.

**Max tries behavior**: When `max_tries` is reached, the loop completes the step successfully even if reviews haven't all approved. The loop doesn't fail the task when max tries is exceeded.

**Git diff**: The git diff is captured after each iteration's implementation/iteration steps complete, and is passed to review steps via the `%{diff}` interpolation variable.

**Failure handling**: If any implement, iterate, or review step returns invalid data or raises an exception, the entire agent_review_loop step is marked as failed and the task stops.

**Step naming**: The `agent_review_loop` counts as a single pipeline step with the name you provide (e.g., `:refactor_code`), not separate steps for each iteration.

### Complete Example

```ruby
class DocumentationPipeline < AgentC::Pipeline
  agent_review_loop(
    :write_documentation,
    max_tries: 3,
    implement: [:draft_readme, :draft_examples],
    iterate: [:improve_readme, :improve_examples],
    review: [:technical_review, :style_review]
  )

  step(:publish) do
    # Only reached if reviews passed or max_tries exceeded
    record.update!(published: true)
  end
end
```

With a record that tracks review history:

```ruby
record(:documentation) do
  schema do |t|
    t.text(:readme_content)
    t.text(:examples_content)
    t.json(:review_history, default: [])
    t.boolean(:published, default: false)
  end

  def add_review(diff:, feedbacks:)
    self.review_history << {
      iteration: review_history.length + 1,
      timestamp: Time.now.iso8601,
      diff_size: diff.length,
      feedback_count: feedbacks.length,
      feedbacks: feedbacks
    }
    save!
  end

  def i18n_attributes
    attributes.merge(
      total_reviews: review_history.length,
      last_feedback: review_history.last&.dig("feedbacks")&.join("\n---\n") || "none"
    )
  end
end
```

### When to Use agent_review_loop vs rewind_to!

Use `agent_review_loop` when:
- The review and iteration logic is straightforward and consistent
- You want a declarative approach with less boilerplate
- Multiple reviewers are involved
- You want automatic feedback collection and interpolation

Use `rewind_to!` when:
- You need custom logic to determine whether to retry
- The retry conditions are complex or context-dependent
- You need to rewind to steps other than the immediate previous one
- You want explicit control over the retry logic
