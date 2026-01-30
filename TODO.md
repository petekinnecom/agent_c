# TODOs

Things I'd like to work on:

- Make injecting a Chat record simpler.
- Make injecting Git simpler (make injecting anything easier)
- Add a request queue to AgentC::Chat so that we can rate-limit and retry on error
- Use spring for run_rails_test, but add a timeout condition where it kills the
  process if no stdout appears for a while and tries again without spring.
- tool calls should write the full results to file (except for readfile) and pass
  back a reference for future queries. For example, if RunRailsTest gives way too
  much output, we have to truncate but how to see the rest?
