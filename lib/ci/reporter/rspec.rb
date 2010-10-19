# Copyright (c) 2006-2010 Nick Sieger <nicksieger@gmail.com>
# See the file LICENSE.txt included with the distribution for
# software license details.

require 'ci/reporter/core'
tried_gem = false
begin
  require 'rspec'
  require 'rspec/core/formatters/progress_formatter'
  require 'rspec/core/formatters/base_formatter'
rescue LoadError
  unless tried_gem
    tried_gem = true
    require 'rubygems'
    gem 'rspec'
    retry
  end
end

module CI
  module Reporter
    # Wrapper around a <code>RSpec</code> error or failure to be used by the test suite to interpret results.
    class RSpecFailure
      def initialize(example)
        @example = example
      end

      def failure?
        @example.execution_result[:status] == 'failed'
      end

      def error?
        !failure?
      end

      def name() @example.execution_result[:exception_encountered].class.name end
      def message() @example.execution_result[:exception_encountered].message end
      def location() @example.execution_result[:exception_encountered].backtrace.join("\n") end
    end

    # Custom +RSpec+ formatter used to hook into the spec runs and capture results.
    class RSpec < ::RSpec::Core::Formatters::BaseFormatter
      attr_accessor :report_manager
      attr_accessor :formatter
      def initialize(*args)
        super
        @formatter ||= ::RSpec::Core::Formatters::ProgressFormatter.new(*args)
        @report_manager = ReportManager.new("spec")
        @suite = nil
      end

      def start(spec_count)
        @start = Time.now
        @formatter.start(spec_count)
      end

      # rspec 0.9
      def add_behaviour(name)
        @formatter.add_behaviour(name)
        new_suite(name)
      end

      # Compatibility with rspec < 1.2.4
      def add_example_group(example_group)
        @formatter.add_example_group(example_group)
        new_suite(example_group.description)
      end

      # rspec >= 1.2.4
      def example_group_started(example_group)
        @formatter.example_group_started(example_group)
        description = example_group.ancestors.reverse.map(&:description).join(' ')
        new_suite(description)
      end

      def example_started(example)
        @formatter.example_started(example)
        example = example.description if example.respond_to?(:description)
        spec = TestCase.new example
        @suite.testcases << spec
        spec.start
      end

      def example_failed(example)
        name = example.full_description

        @formatter.example_failed(example)
        # In case we fail in before(:all)
        if @suite.testcases.empty?
          example_started(example)
        end
        spec = @suite.testcases.last
        spec.finish
        spec.failures << RSpecFailure.new(example)
      end

      def example_passed(example)
        @formatter.example_passed(example)
        spec = @suite.testcases.last
        spec.finish
      end

      def example_pending(*args)
        @formatter.example_pending(*args)
        spec = @suite.testcases.last
        spec.finish
        spec.name = "#{spec.name} (PENDING)"
        spec.skipped = true
      end

      def start_dump
        @formatter.start_dump
      end

      def dump_failure(*args)
        @formatter.dump_failure(*args)
      end

      def dump_summary(*args)
        @formatter.dump_summary(*args)
        write_report
      end

      def dump_pending
        @formatter.dump_pending
      end

      def close
        @formatter.close
      end

      private
      def write_report
        @suite.finish
        @report_manager.write_report(@suite)
      end

      def new_suite(name)
        write_report if @suite
        @suite = TestSuite.new name
        @suite.start
      end
    end

    class RSpecDoc < RSpec
      def initialize(*args)
        @formatter = ::RSpec::Core::Formatters::SpecdocFormatter.new(*args)
        super
      end
    end
  end
end
