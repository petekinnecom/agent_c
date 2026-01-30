# frozen_string_literal: true

require "bundler/setup"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "."
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = false
  t.warning = false
  # Enable parallel test execution based on number of processors
  ENV["MT_CPU"] ||= Etc.nprocessors.to_s
end

task default: :test
