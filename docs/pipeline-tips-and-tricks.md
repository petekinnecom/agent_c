# Pipeline Tips and Tricks

This document contains useful patterns and techniques for working with AgentC pipelines.

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
