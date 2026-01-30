# frozen_string_literal: true

require "ruby_llm"
require "active_support/all"

# this shows an annyoing warning
begin
  old_stderr = $stderr
  $stderr = StringIO.new
  require "async"
  require "async/semaphore"
  $stderr = old_stderr
ensure
end

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.setup

# Configure i18n how I like it:

require "i18n"
MissingTranslation = Class.new(StandardError)
I18n.singleton_class.prepend(Module.new do
  def t(*a, **p)
    super(*a, __force_exception_raising__: true, **p)
  end
end)
I18n.exception_handler = ->(_, _, key, _) { raise MissingTranslation.new(key.inspect) }
I18n.load_path << File.join(__dir__, "./agent_c/prompts.yml")

module AgentC; end
