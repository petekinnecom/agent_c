# Rules

- Leave modules modules if they do not need state. If they apply behaviors to other schema/classes leave them modules.
- Prefer to not store lambdas as variables unless necessary. If they are just going to be passed to other methods, leave them as blocks
- If a class is not trivial (eg, more than one method and/or more than like 30 lines) then extract it to its own file.
- This project is using Zeitwerk. You should not use require_relative, just match the module names to file path and it will load automatically.
- When you commit, use the --no-gpg-sign flag. Start commit messages with "claude: "
- DO NOT add example scripts. Either add it to the readme or make a test.
- DO NOT add documentation outside of the README
- DO NOT program defensively. If something should respond_to?() a method then just invoke the method. An error is better than a false positive
- If you need to test a one-off script, write a test-case and run it instad of writing a temporary file or using a giant shell script
- DO NOT edit the singleton class of an object. If you think you need to do this, ideas for avoiding: inject an object, create a module and include it, make a base class.

# TESTING

- We do not use stubbing in our test. If you need to stub something (or monkey-patch it) to test it, that thing should be injectable.
- Run tests with `bin/rake test` You can pass TESTOPTS to run a specific file.

# Style

- For multiline Strings always use a HEREDOC
