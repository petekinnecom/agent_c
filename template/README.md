# Overview

This directory contains a small script demonstrating how to run a batch of pipelines.

For each `summary` record created, Claude will choose a random file, summarize it, and write the summary to disk. Then our pipeline commits the changes at the end.

It creates two records and runs them across two worktrees.

The main entrypoint is the Rakefile.


### Running the Batch

You'll need to set the relevant environment variables specified in the Config. (The environment variables necessary assume you're using Claude on Bedrock.)

Then run:

```sh
bin/rake run
# => Summary report:
# => Succeeded: 2
# => Pending: 0
# => Failed: 0
# => Run cost: $0.31
# => Project total cost: $1.67
# => ---
# => task: 1 - wrote summary to /tmp/example-worktrees/summary-examples-0/VERSIONED_STORE_BASE_SUMMARY.md
# => task: 2 - wrote summary to /tmp/example-worktrees/summary-examples-1/SUMMARY-es.md
```

### Watching progress

You can tail the logs with:

```sh
# See EVERYTHING
tail -f log/run.log

# See just progress
tail -f log/run.log | grep INFO
```

### Poking around the data

```sh
bin/rake console
```

### Resetting state

Delete the state stored in the `./tmp` directory to start all over:

```sh
rm -rf ./tmp
```

### Run the tests:

```sh
bin/rake test
```
