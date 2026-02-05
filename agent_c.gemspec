# frozen_string_literal: true

require_relative "lib/agent_c/version"

Gem::Specification.new do |spec|
  spec.name = "agent_c"
  spec.version = AgentC::VERSION
  spec.authors = ["Pete Kinnecom"]
  spec.email = ["git@k7u7.com"]

  spec.summary = <<~TEXT.strip
    Batch processing for pipelines of steps for AI. AgentC, get it?
  TEXT
  spec.homepage = "https://github.com/petekinnecom/agent_c"
  spec.license = "WTFPL"
  spec.required_ruby_version = ">= 3.0.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency("zeitwerk", "~> 2.7")
  spec.add_dependency("activerecord", "~> 8.1")
  spec.add_dependency("sqlite3", "~> 2.9")
  spec.add_dependency("async", "~> 2.35")
  spec.add_dependency("ruby_llm", "~> 1.9")
  spec.add_dependency("json-schema", "~> 6.1")
end
