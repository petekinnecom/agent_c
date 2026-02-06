# TODOs

Things I'd like to work on:

- Make injecting a Chat record simpler.
- Make injecting Git simpler (make injecting anything easier)
- Add a request queue to AgentC::Chat so that we can rate-limit and retry on error
- Use spring for run_rails_test, but add a timeout condition where it kills the process if no stdout appears for a while and tries again without spring.
- tool calls should write the full results to file (except for readfile) and pass back a reference for future queries. For example, if RunRailsTest gives way too much output, we have to truncate but how to see the rest?

## Immplement plan, implement, review looping

Some scratch:

```ruby
agent_iterate_loop(
  :implement_query_object,
  max_tries: 17,
  plan: [
    :plan_step_1,
    :plan_step_2,
  ],
  implement: [
    :implement_step_1,
    :implement_step_2,
  ],
  # optional: defaults to implement
  iterate: [
    :address_feedback_1
  ]
  review: [
    :review_step_1,
    :review_step_2
  ],
)
```

Thoughts:

- This makes a demand on the `response_schema` of the prompts.
- Does the `task` track the looping here or the `record`?
  - Is the progress tracked in memory? This can be one step...
- What if you have multiple `agent_iterate_loop` invocations? How do we store diffs/reviews for each of those?
- The `agent_step` applies the result to the record. If we track it on the task, we could get the attributes to the right place. Can we extend the response schema? The `plan` step definitely needs to update the record, so it needs to specify response_schema. The `implement/iterate` steps *might* need to accept response_schema (eg, path of file created? Or not necessary?, maybe not necessary.)
- Does a failed review trigger plan -> iterate -> review or just iterate -> review
  - The implement/iterate arrays could include "plan" steps so that they know if they're starting from scratch or not.
  - Do we run every review or stop at the first one?


```ruby
def agent_iterate_loop(
  name,
  max_tries: 3,
  implement: [],
  iterate: implement,
  review: [],
)
  step(name) do
    tries = 0

    while(tries < max_tries)
      if tries == 0
        implement.each do |name|
          process_prompt(name)
        end
      else
        iterate.each do |name|
          process_prompt(
            name,
            additional_i18n_attrs: {
              feedback: feedback.join("\n---\n")
            }
          )
        end
      end

      feedbacks = []

      diff = git.diff
      review.each do |name|
        result = process_prompt(
          name,
          schema: -> {
            t.boolean(:pass)
            t.string(:feedback)
          },
          additional_i18n_attrs: {
            diff:
          }
        )

        if !result.fetch("pass")
          feedbacks << result.fetch("feedback")
        end
      end

      if record.respond_to?(:add_review)
        record.add_review(diff:, feedbacks:)
      end

      break if feedbacks.empty?
    end
  end
end
```
