# Cost Reporting

Note: You probably want to make a `Batch`. See the [main README](../README.md)

## Overview

AgentC automatically tracks all LLM interactions in a SQLite database, allowing you to generate detailed cost reports.

## Generating Reports

Track your LLM usage and costs:

```ruby
# See the [configuration](./session-configuration.md) for session args
session = AgentC::Session.new(...)

# Generate a cost report for all projects
AgentC::Costs::Report.call(agent_store: session.agent_store)

# For a specific project
AgentC::Costs::Report.call(
  agent_store: session.agent_store,
  project: 'my_project'
)

# For a specific run
AgentC::Costs::Report.call(
  agent_store: session.agent_store,
  project: 'my_project',
  run_id: 1234567890
)

# Or use the session's cost method for current project/run
puts "Project cost: $#{session.cost.project}"
puts "Run cost: $#{session.cost.run}"
```

## What's Included

The report includes:
- Input/output token counts
- Cache hit rates
- Per-interaction costs
- Total spending
- Pricing for both normal and long-context models

## Report Format

The cost report displays information organized by project and run:

```
Project: my_project
Run ID: 1234567890

Interaction 1 (2024-01-15 10:30:00)
  Input tokens: 1,250
  Output tokens: 450
  Cached tokens: 800
  Cost: $0.0234

Interaction 2 (2024-01-15 10:35:00)
  Input tokens: 2,100
  Output tokens: 680
  Cached tokens: 1,500
  Cost: $0.0356

Total Cost: $0.0590
```

## Cost Optimization Tips

1. **Use cached prompts** - System prompts that rarely change can be cached, significantly reducing costs
2. **Choose appropriate models** - Use lighter models (Haiku) for simple tasks, heavier models (Sonnet/Opus) for complex ones
3. **Batch operations** - Group similar tasks together to maximize cache hits
4. **Monitor costs regularly** - Run cost reports after each pipeline run to identify expensive operations

## Database Schema

All queries are persisted in SQLite with:
- Full conversation history
- Token usage metrics
- Timestamps and metadata
- Tool calls and responses
- Project and run ID associations

This allows for detailed analysis and debugging of AI interactions over time.
