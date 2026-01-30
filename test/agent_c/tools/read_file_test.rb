# frozen_string_literal: true

require_relative "../../test_helper"
require "ruby_llm"
require "fileutils"

module AgentC
  module Tools
    class ReadFileTest < Minitest::Test
      def setup
        @test_dir = File.expand_path("../../../tmp/test_files", __dir__)

        FileUtils.mkdir_p(@test_dir)

        @test_file = File.join(@test_dir, "sample.txt")
        File.write(@test_file, <<~CONTENT)
          Line 1
          Line 2
          Line 3
          Line 4
          Line 5
          Line 6
          Line 7
          Line 8
          Line 9
          Line 10
        CONTENT

        @tool = ReadFile.new(working_dir: @test_dir)

        # Change to test directory so relative paths work
        @original_dir = Dir.pwd
        Dir.chdir(@test_dir)
      end

      def teardown
        Dir.chdir(@original_dir)
        FileUtils.rm_rf(@test_dir)
      end

      def test_reads_entire_file_with_line_numbers

        result = @tool.execute(path: "sample.txt")

        assert_match(/1: Line 1/, result)
        assert_match(/2: Line 2/, result)
        assert_match(/10: Line 10/, result)

        # Verify all lines are present
        (1..10).each do |i|
          assert_match(/#{i}: Line #{i}/, result)
        end
      end

      def test_line_range_with_line_numbers
        result = @tool.execute(path: "sample.txt", line_range_start: 2, line_range_end: 5)

        assert_match(/Returning lines 3-6/, result)
        assert_match(/3: Line 3/, result)
        assert_match(/4: Line 4/, result)
        assert_match(/5: Line 5/, result)
        assert_match(/6: Line 6/, result)

        # Should not include lines outside range
        refute_match(/2: Line 2/, result)
        refute_match(/7: Line 7/, result)
      end

      def test_line_numbers_align_properly
        # Create a file with 100+ lines to test alignment
        large_file = File.join(@test_dir, "large.txt")
        File.write(large_file, (1..150).map { |i| "Content line #{i}" }.join("\n"))

        result = @tool.execute(path: "large.txt", line_range_start: 0, line_range_end: 20)

        lines = result.split("\n")
        content_lines = lines[2..-1] # Skip the header

        # Check single-digit line numbers have proper spacing
        first_line = content_lines.first
        assert_match(/^\s*1: Content line 1/, first_line)

        # Check double-digit line numbers
        tenth_line = content_lines[9]
        assert_match(/^10: Content line 10/, tenth_line)
      end

      def test_line_numbers_align_for_large_line_numbers
        # Test with lines 95-105 to verify alignment across 2-3 digit boundary
        large_file = File.join(@test_dir, "large.txt")
        File.write(large_file, (1..150).map { |i| "Content line #{i}" }.join("\n"))

        result = @tool.execute(path: "large.txt", line_range_start: 94, line_range_end: 104)

        lines = result.split("\n")
        content_lines = lines[2..-1] # Skip the header

        # All line numbers should be aligned with 3-digit width
        content_lines.each do |line|
          assert_match(/^\s*\d+: /, line)
        end

        # Verify specific line numbers are present
        assert_match(/95: Content line 95/, result)
        assert_match(/100: Content line 100/, result)
        assert_match(/105: Content line 105/, result)
      end

      def test_file_not_found
        result = @tool.execute(path: "nonexistent.txt")
        assert_equal "File not found", result
      end

      def test_path_outside_current_directory
        result = @tool.execute(path: "/etc/passwd")
        assert_equal(
          "Path: /etc/passwd not acceptable. Must be a child of directory: #{@test_dir}.",
          result
        )
      end

      def test_truncation_with_line_numbers
        # Create a file with more than 300 lines
        huge_file = File.join(@test_dir, "huge.txt")
        File.write(huge_file, (1..500).map { |i| "Line #{i}" }.join("\n"))

        result = @tool.execute(path: "huge.txt")

        assert_match(/Returning lines 1-300, out of 500 total lines/, result)
        assert_match(/1: Line 1/, result)
        assert_match(/300: Line 300/, result)
        refute_match(/301: Line 301/, result)
      end

      def test_line_range_start_only
        result = @tool.execute(path: "sample.txt", line_range_start: 5)

        assert_match(/Returning lines 6-10/, result)
        assert_match(/6: Line 6/, result)
        assert_match(/10: Line 10/, result)
        refute_match(/5: Line 5/, result)
      end

      def test_empty_file
        empty_file = File.join(@test_dir, "empty.txt")
        File.write(empty_file, "")

        result = @tool.execute(path: "empty.txt")
        assert_equal "", result
      end

      def test_single_line_file
        single_file = File.join(@test_dir, "single.txt")
        File.write(single_file, "Only one line")

        result = @tool.execute(path: "single.txt")
        assert_equal "1: Only one line", result
      end
    end
  end
end
