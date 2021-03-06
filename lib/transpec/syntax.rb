# coding: utf-8

require 'transpec/context_error'
require 'transpec/static_context_inspector'
require 'transpec/record'
require 'transpec/report'
require 'active_support/concern'

module Transpec
  class Syntax
    module Collection
      def inherited(subclass)
        all_syntaxes << subclass
      end

      def require_all
        pattern = File.join(File.dirname(__FILE__), 'syntax', '*.rb')
        Dir.glob(pattern) do |path|
          require path
        end
      end

      def all_syntaxes
        @subclasses ||= []
      end

      def standalone_syntaxes
        @standalone_syntaxes ||= all_syntaxes.select(&:standalone?)
      end
    end
  end
end

module Transpec
  class Syntax
    module Rewritable
      private

      def remove(range)
        @source_rewriter.remove(range)
      end

      def insert_before(range, content)
        @source_rewriter.insert_before(range, content)
      end

      def insert_after(range, content)
        @source_rewriter.insert_after(range, content)
      end

      def replace(range, content)
        @source_rewriter.replace(range, content)
      end
    end
  end
end

module Transpec
  class Syntax
    module DynamicAnalysis
      extend ActiveSupport::Concern

      module ClassMethods
        def add_dynamic_analysis_request(&block)
          dynamic_analysis_requests << block
        end

        def dynamic_analysis_requests
          @dynamic_analysis_requests ||= []
        end

        def dynamic_analysis_target_node?(node)
          target_node?(node)
        end
      end

      def register_request_for_dynamic_analysis(rewriter)
        self.class.dynamic_analysis_requests.each do |request|
          instance_exec(rewriter, &request)
        end
      end
    end
  end
end

module Transpec
  class Syntax
    extend Collection
    include Rewritable, DynamicAnalysis

    attr_reader :node, :source_rewriter, :runtime_data, :report

    def self.standalone?
      true
    end

    def self.snake_case_name
      @snake_cake_name ||= begin
        class_name = name.split('::').last
        class_name.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end
    end

    # The default common method for .conversion_target_node? and .dynamic_analysis_target_node?.
    # If they should behave differently, override either or both.
    def self.target_node?(node, runtime_data = nil)
      false
    end

    def self.conversion_target_node?(node, runtime_data = nil)
      target_node?(node, runtime_data)
    end

    def initialize(node, source_rewriter = nil, runtime_data = nil, report = nil)
      @node = node
      @source_rewriter = source_rewriter
      @runtime_data = runtime_data
      @report = report || Report.new
    end

    def static_context_inspector
      @static_context_inspector ||= StaticContextInspector.new(@node)
    end

    def parent_node
      @node.parent_node
    end

    def expression_range
      @node.loc.expression
    end

    private

    def runtime_node_data(node)
      @runtime_data && @runtime_data[node]
    end
  end
end
