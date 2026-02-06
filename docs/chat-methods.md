# Chat Methods

**Note:** For batch processing and structured workflows, use [Batch and Pipeline](../README.md) instead. The methods below are for direct chat interactions and one-off requests.

AgentC provides several methods for interacting with LLMs, each optimized for different use cases.

## Creating Chats

```ruby
# See the [configuration](./session-configuration.md) for session args
session = Session.new(...)

chat = session.chat(
  tools: [:read_file, :edit_file],
  cached_prompts: ["You are a helpful assistant"],
  workspace_dir: Dir.pwd
)
```

## Chat.ask(message)

Basic interaction - send a message and get a response:

```ruby
chat = session.chat
response = chat.ask("Explain recursion in simple terms")
```

## Chat.get(message, schema:, confirm:, out_of:)

Get a structured response with optional confirmation:

```ruby
# Get a simple answer
answer = chat.get("What is 2 + 2?")

# Get structured response using AgentC::Schema.result
# This creates a schema that accepts either success or error responses
#
# You can make your own schema using RubyLLM::Schema, but
# this is a pretty standard approach. It will allow the LLM
# to indicate that they could not fulfill your request and
# give a reason why.
#
# The response will look like one of the following:
# Success response (just the data fields):
# {
#   name: "...",
#   email: "...",
# }
# OR error response:
# {
#   unable_to_fulfill_request_error: "some reason why it couldn't do it"
# }

schema = AgentC::Schema.result do
  string(:name, description: "Person's name")
  string(:email, description: "Person's email")
end

result = chat.get(
  "Extract the name and email from this text: 'Contact John at john@example.com'",
  schema: schema
)
# => { "name" => "John", "email" => "john@example.com" }

# If the LLM can't complete the task, it returns an error response:
# => { "unable_to_fulfill_request_error" => "No email found in the text" }
```

### Using confirm and out_of for consensus

LLMs are non-deterministic and can give different answers to the same question. The `confirm` feature asks the question multiple times and only accepts an answer when it appears at least `confirm` times out of `out_of` attempts. This gives you much higher confidence the answer isn't a hallucination or random variation.

```ruby
class YesOrNoSchema < RubyLLM::Schema
  string(:value, enum: ["yes", "no"])
end

confirmed = chat.get(
  "Is vanilla better than chocolate?",
  confirm: 2,    # Need 2 matching answers
  out_of: 3,      # Out of 3 attempts max
  schema: YesOrNoSchema
)
```

## Chat.refine(message, schema:, times:)

Iteratively refine a response by having the LLM review and improve its own answer.

The refine feature asks your question, gets an answer, then asks the LLM to review that answer for accuracy and improvements. This repeats for the specified number of times. Each iteration gives the LLM a chance to catch mistakes, add detail, or improve quality.

This works because LLMs are often better at *reviewing* content than generating it perfectly the first time - like having an editor review a draft. It's especially effective for creative tasks, complex analysis, or code generation where iterative improvement leads to higher quality outputs.

```ruby
HaikuSchema = RubyLLM::Schema.object(
  haiku: RubyLLM::Schema.string
)

refined_answer = chat.refine(
  "Write a haiku about programming",
  schema: HaikuSchema,
  times: 3  # LLM reviews and refines its answer 3 times
)
```

## Session.prompt() - One-Off Requests

For single-shot requests where you don't need a persistent chat, use `session.prompt()`:

```ruby
# See the [configuration](./session-configuration.md) for session args
session = Session.new(...)

# Simple one-off request
result = session.prompt(
  prompt: "What is the capital of France?",
  schema: -> { string(:answer) }
)
# => ChatResponse with success/error status

# With tools and custom settings
result = session.prompt(
  prompt: "Read the README file and summarize it",
  schema: -> { string(:summary) },
  tools: [:read_file],
  tool_args: { workspace_dir: '/path/to/project' },
  cached_prompt: ["You are a helpful documentation assistant"]
)

if result.success?
  puts result.data['summary']
else
  puts "Error: #{result.error_message}"
end
```

This is equivalent to creating a chat, calling `get()`, and handling the response, but more concise for one-off requests.

## Cached Prompts

To optimize token usage and reduce costs, you can use cached prompts. Cached prompts are stored in the API provider's cache and can significantly reduce the number of input tokens charged on subsequent requests.

```ruby
# Provide cached prompts that will be reused across conversations
cached_prompts = [
  "You are a helpful coding assistant specialized in Ruby.",
  "Always write idiomatic Ruby code following Ruby community best practices."
]

chat = session.chat(cached_prompts: cached_prompts)
response = chat.ask("Write a method to calculate fibonacci numbers")
```

The first request will incur cache creation costs, but subsequent requests with the same cached prompts will use significantly fewer tokens, reducing overall API costs.
