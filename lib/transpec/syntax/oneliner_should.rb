# coding: utf-8

require 'transpec/syntax'
require 'transpec/syntax/mixin/should_base'
require 'transpec/rspec_dsl'
require 'transpec/util'
require 'active_support/inflector/methods'

module Transpec
  class Syntax
    class OnelinerShould < Syntax
      include Mixin::ShouldBase, RSpecDSL, Util

      attr_reader :current_syntax_type

      def self.target_method?(receiver_node, method_name)
        receiver_node.nil? && [:should, :should_not].include?(method_name)
      end

      def initialize(node, source_rewriter = nil, runtime_data = nil, report = nil)
        super
        @current_syntax_type = :should
      end

      def expectize!(negative_form = 'not_to', parenthesize_matcher_arg = true)
        replacement = 'is_expected.'
        replacement << (positive? ? 'to' : negative_form)
        replace(should_range, replacement)

        @current_syntax_type = :expect
        operator_matcher.convert_operator!(parenthesize_matcher_arg) if operator_matcher

        register_record(negative_form)
      end

      def convert_have_items_to_standard_should!
        return if have_matcher.project_requires_collection_matcher?

        insert_example_description!

        subject_source = have_matcher.build_replacement_subject_source('subject')
        insert_before(expression_range, "#{subject_source}.")

        have_matcher.convert_to_standard_expectation!

        @report.records << OnelinerShouldHaveRecord.new(self, have_matcher)
      end

      # rubocop:disable LineLength
      def convert_have_items_to_standard_expect!(negative_form = 'not_to', parenthesize_matcher_arg = true)
        # rubocop:enable LineLength
        return if have_matcher.project_requires_collection_matcher?

        insert_example_description!

        subject_source = have_matcher.build_replacement_subject_source('subject')
        expect_to_source = "expect(#{subject_source})."
        expect_to_source << (positive? ? 'to' : negative_form)
        replace(should_range, expect_to_source)

        @current_syntax_type = :expect
        have_matcher.convert_to_standard_expectation!

        @report.records << OnelinerShouldHaveRecord.new(self, have_matcher, negative_form)
      end

      def example_has_description?
        send_node = example_block_node.children.first
        !send_node.children[2].nil?
      end

      def build_description(size)
        description = positive? ? 'has ' : 'does not have '

        case have_matcher.have_method_name
        when :have_at_least then description << 'at least '
        when :have_at_most  then description << 'at most '
        end

        items = have_matcher.items_name

        if positive? && size == '0'
          size = 'no'
        elsif size == '1'
          items = ActiveSupport::Inflector.singularize(have_matcher.items_name)
        end

        description << "#{size} #{items}"
      end

      private

      def insert_example_description!
        fail 'This one-liner #should does not have #have matcher!' unless have_matcher

        unless example_has_description?
          insert_before(example_block_node.loc.begin, "'#{generated_description}' ")
        end

        indentation = indentation_of_line(example_block_node)

        unless linefeed_at_beginning_of_block?
          replace(left_curly_and_whitespaces_range, "do\n#{indentation}  ")
        end

        unless linefeed_at_end_of_block?
          replace(whitespaces_and_right_curly_range, "\n#{indentation}end")
        end
      end

      def example_block_node
        return @example_block_node if instance_variable_defined?(:@example_block_node)

        @example_block_node = @node.each_ancestor_node.find do |node|
          next false unless node.type == :block
          send_node = node.children.first
          receiver_node, method_name, = *send_node
          next false if receiver_node
          EXAMPLE_METHODS.include?(method_name)
        end
      end

      def generated_description
        build_description(have_matcher.size_source)
      end

      def linefeed_at_beginning_of_block?
        beginning_to_body_range = example_block_node.loc.begin.join(expression_range.begin)
        beginning_to_body_range.source.include?("\n")
      end

      def linefeed_at_end_of_block?
        body_to_end_range = expression_range.end.join(example_block_node.loc.end)
        body_to_end_range.source.include?("\n")
      end

      def left_curly_and_whitespaces_range
        expand_range_to_adjacent_whitespaces(example_block_node.loc.begin, :end)
      end

      def whitespaces_and_right_curly_range
        expand_range_to_adjacent_whitespaces(example_block_node.loc.end, :begin)
      end

      def register_record(negative_form_of_to)
        original_syntax = 'it { should'
        converted_syntax = 'it { is_expected.'

        if positive?
          converted_syntax << 'to'
        else
          original_syntax << '_not'
          converted_syntax << negative_form_of_to
        end

        [original_syntax, converted_syntax].each do |syntax|
          syntax << ' ... }'
        end

        @report.records << Record.new(original_syntax, converted_syntax)
      end

      class OnelinerShouldHaveRecord < Have::HaveRecord
        def initialize(should, have, negative_form_of_to = nil)
          @should = should
          @have = have
          @negative_form_of_to = negative_form_of_to
        end

        def original_syntax
          @original_syntax ||= begin
            syntax = @should.example_has_description? ? "it '...' do" : 'it {'
            syntax << " #{@should.method_name} #{@have.have_method_name}(n).#{original_items} "
            syntax << (@should.example_has_description? ? 'end' : '}')
          end
        end

        def converted_syntax
          @converted_syntax ||= begin
            syntax = converted_description
            syntax << ' '
            syntax << converted_expectation
            syntax << ' '
            syntax << @have.build_replacement_matcher_source('n')
            syntax << ' end'
          end
        end

        def converted_description
          if @should.example_has_description?
            "it '...' do"
          else
            "it '#{@should.build_description('n')}' do"
          end
        end

        def converted_expectation
          case @should.current_syntax_type
          when :should
            "#{converted_subject}.#{@should.method_name}"
          when :expect
            "expect(#{converted_subject})." + (@should.positive? ? 'to' : @negative_form_of_to)
          end
        end

        def converted_subject
          build_converted_subject('subject')
        end
      end
    end
  end
end
