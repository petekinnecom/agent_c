# frozen_string_literal: true

require "versioned_store"
require "agent_c"
require "i18n"
require "zeitwerk"

loader = Zeitwerk::Loader.new
loader.push_dir(File.expand_path(__dir__))
loader.setup
