# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "ruby_llm"
require_relative "../../test_helper"

module AgentC
  module Tools
    class EditFileTest < Minitest::Test
      def setup
        @test_dir = Dir.mktmpdir("edit_file_test")
        @original_dir = Dir.pwd
        Dir.chdir(@test_dir)

        @tool = EditFile.new(working_dir: @test_dir)
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@test_dir)
      end

      def test_overwrite_mode_creates_new_file
        result = @tool.execute(
          path: "test.txt",
          mode: "overwrite",
          content: "Hello, World!"
        )

        assert_equal true, result
        assert_equal "Hello, World!", File.read("test.txt")
      end

      def test_overwrite_mode_replaces_existing_file
        File.write("test.txt", "Old content")

        result = @tool.execute(
          path: "test.txt",
          mode: "overwrite",
          content: "New content"
        )

        assert_equal true, result
        assert_equal "New content", File.read("test.txt")
      end

      def test_replace_lines_mode
        File.write("test.txt", "line 1\nline 2\nline 3\nline 4\nline 5\n")

        result = @tool.execute(
          path: "test.txt",
          mode: "replace_lines",
          content: "replaced line 2\nreplaced line 3",
          start_line: 2,
          end_line: 3
        )

        assert_equal true, result
        expected = "line 1\nreplaced line 2\nreplaced line 3\nline 4\nline 5\n"
        assert_equal expected, File.read("test.txt")
      end

      def test_replace_lines_requires_start_and_end_line
        File.write("test.txt", "line 1\nline 2\n")

        result = @tool.execute(
          path: "test.txt",
          mode: "replace_lines",
          content: "new content",
          start_line: 1
        )

        assert_equal "start_line and end_line required for replace_lines mode", result
      end

      def test_replace_lines_validates_line_order
        File.write("test.txt", "line 1\nline 2\n")

        result = @tool.execute(
          path: "test.txt",
          mode: "replace_lines",
          content: "new content",
          start_line: 3,
          end_line: 1
        )

        assert_equal "start_line must be <= end_line", result
      end

      def test_insert_at_line_mode
        File.write("test.txt", "line 1\nline 2\nline 3\n")

        result = @tool.execute(
          path: "test.txt",
          mode: "insert_at_line",
          content: "inserted line",
          start_line: 2
        )

        assert_equal true, result
        expected = "line 1\ninserted line\nline 2\nline 3\n"
        assert_equal expected, File.read("test.txt")
      end

      def test_insert_at_line_at_start_of_file
        File.write("test.txt", "line 1\nline 2\n")

        result = @tool.execute(
          path: "test.txt",
          mode: "insert_at_line",
          content: "new first line",
          start_line: 1
        )

        assert_equal true, result
        expected = "new first line\nline 1\nline 2\n"
        assert_equal expected, File.read("test.txt")
      end

      def test_insert_at_line_requires_start_line
        File.write("test.txt", "line 1\n")

        result = @tool.execute(
          path: "test.txt",
          mode: "insert_at_line",
          content: "new line"
        )

        assert_equal "start_line required for insert_at_line mode", result
      end

      def test_append_mode
        File.write("test.txt", "existing content\n")

        result = @tool.execute(
          path: "test.txt",
          mode: "append",
          content: "appended content"
        )

        assert_equal true, result
        expected = "existing content\nappended content\n"
        assert_equal expected, File.read("test.txt")
      end

      def test_append_mode_creates_new_file
        result = @tool.execute(
          path: "test.txt",
          mode: "append",
          content: "new content"
        )

        assert_equal true, result
        assert_equal "new content\n", File.read("test.txt")
      end

      def test_path_must_be_child_of_current_directory
        result = @tool.execute(
          path: "/etc/passwd",
          mode: "overwrite",
          content: "malicious"
        )

        assert_equal(
          "Path: /etc/passwd not acceptable. Must be a child of directory: #{@test_dir}.",
          result
        )
      end

      def test_creates_parent_directories
        result = @tool.execute(
          path: "deep/nested/file.txt",
          mode: "overwrite",
          content: "content"
        )

        assert_equal true, result
        assert File.exist?("deep/nested/file.txt")
        assert_equal "content", File.read("deep/nested/file.txt")
      end

      def test_ruby_syntax_check_passes
        result = @tool.execute(
          path: "valid.rb",
          mode: "overwrite",
          content: "puts 'Hello, World!'\n"
        )

        assert_equal true, result
      end

      def test_ruby_syntax_check_fails
        result = @tool.execute(
          path: "invalid.rb",
          mode: "overwrite",
          content: "puts 'Hello, World!\nend\n"
        )

        assert_match(/File successfully edited, but syntax errors were found:/, result)
        assert_match(/syntax error/, result)
      end

      def test_non_ruby_files_skip_syntax_check
        result = @tool.execute(
          path: "test.txt",
          mode: "overwrite",
          content: "any content @#$%"
        )

        assert_equal true, result
      end

      def test_multiline_content
        content = <<~CONTENT
          def hello
            puts "Hello"
          end
        CONTENT

        result = @tool.execute(
          path: "test.rb",
          mode: "overwrite",
          content: content
        )

        assert_equal true, result
        assert_equal content, File.read("test.rb")
      end
    end
  end
end
