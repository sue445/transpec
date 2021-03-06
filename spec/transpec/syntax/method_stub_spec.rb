# coding: utf-8

require 'spec_helper'
require 'transpec/syntax/method_stub'
require 'transpec'

module Transpec
  class Syntax
    describe MethodStub do
      include_context 'parsed objects'
      include_context 'syntax object', MethodStub, :method_stub_object

      let(:record) { method_stub_object.report.records.first }

      describe '.conversion_target_node?' do
        let(:send_node) do
          ast.each_descendent_node do |node|
            next unless node.type == :send
            method_name = node.children[1]
            next unless method_name == :stub
            return node
          end
          fail 'No #stub node is found!'
        end

        context 'when #stub node is passed' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo)
                end
              end
            END
          end

          it 'returns true' do
            MethodStub.conversion_target_node?(send_node).should be_true
          end
        end

        context 'when Factory.stub node is passed' do
          let(:source) do
            <<-END
              describe 'example' do
                it "is not RSpec's #stub" do
                  Factory.stub(:foo)
                end
              end
            END
          end

          it 'returns false' do
            MethodStub.conversion_target_node?(send_node).should be_false
          end
        end

        context 'with runtime information' do
          include_context 'dynamic analysis objects'

          context "when RSpec's #stub node is passed" do
            let(:source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo' do
                    subject.stub(:foo)
                  end
                end
              END
            end

            it 'returns true' do
              MethodStub.conversion_target_node?(send_node, runtime_data).should be_true
            end
          end

          context 'when another #stub node is passed' do
            let(:source) do
              <<-END
                module AnotherStubProvider
                  def self.stub(*args)
                  end
                end

                describe 'example' do
                  it "is not RSpec's #stub" do
                    AnotherStubProvider.stub(:something)
                  end
                end
              END
            end

            it 'returns false' do
              MethodStub.conversion_target_node?(send_node, runtime_data).should be_false
            end
          end

          context "when Factory.stub node is passed and it's RSpec's #stub" do
            let(:source) do
              <<-END
                module Factory
                end

                describe 'example' do
                  it 'responds to #foo' do
                    Factory.stub(:foo)
                  end
                end
              END
            end

            it 'returns true' do
              MethodStub.conversion_target_node?(send_node, runtime_data).should be_true
            end
          end

          context 'when Factory.stub node is passed and it has not been run' do
            let(:source) do
              <<-END
                module Factory
                end

                describe 'example' do
                  it 'responds to #foo' do
                    true || Factory.stub(:foo)
                  end
                end
              END
            end

            it 'returns false' do
              MethodStub.conversion_target_node?(send_node, runtime_data).should be_false
            end
          end
        end
      end

      describe '#method_name' do
        let(:source) do
          <<-END
            describe 'example' do
              it 'responds to #foo' do
                subject.stub(:foo)
              end
            end
          END
        end

        it 'returns the method name' do
          method_stub_object.method_name.should == :stub
        end
      end

      describe '#allowize!' do
        before do
          method_stub_object.allowize!(rspec_version) unless example.metadata[:no_before_allowize!]
        end

        let(:rspec_version) { Transpec.required_rspec_version }

        context 'when it is `subject.stub(:method)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  allow(subject).to receive(:foo)
                end
              end
            END
          end

          it 'converts into `allow(subject).to receive(:method)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record `obj.stub(:message)` -> `allow(obj).to receive(:message)`' do
            record.original_syntax.should  == 'obj.stub(:message)'
            record.converted_syntax.should == 'allow(obj).to receive(:message)'
          end

          context 'and #allow and #receive are not available in the context', :no_before_allowize! do
            context 'and the context is determinable statically' do
              let(:source) do
                <<-END
                  describe 'example' do
                    class TestRunner
                      def run
                        'something'.stub(:foo)
                      end
                    end

                    it 'responds to #foo' do
                      TestRunner.new.run
                    end
                  end
                END
              end

              context 'with runtime information' do
                include_context 'dynamic analysis objects'

                it 'raises ContextError' do
                  -> { method_stub_object.allowize!(rspec_version) }
                    .should raise_error(ContextError)
                end
              end

              context 'without runtime information' do
                it 'raises ContextError' do
                  -> { method_stub_object.allowize!(rspec_version) }
                    .should raise_error(ContextError)
                end
              end
            end

            context 'and the context is not determinable statically' do
              let(:source) do
                <<-END
                  def my_eval(&block)
                    Object.new.instance_eval(&block)
                  end

                  describe 'example' do
                    it 'responds to #foo' do
                      my_eval { 'something'.stub(:foo) }
                    end
                  end
                END
              end

              context 'with runtime information' do
                include_context 'dynamic analysis objects'

                it 'raises ContextError' do
                  -> { method_stub_object.allowize!(rspec_version) }
                    .should raise_error(ContextError)
                end
              end

              context 'without runtime information' do
                it 'does not raise ContextError' do
                  -> { method_stub_object.allowize!(rspec_version) }
                    .should_not raise_error
                end
              end
            end
          end
        end

        context 'when it is `subject.stub!(:method)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub!(:foo)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  allow(subject).to receive(:foo)
                end
              end
            END
          end

          it 'converts into `allow(subject).to receive(:method)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record `obj.stub!(:message)` -> `allow(obj).to receive(:message)`' do
            record.original_syntax.should  == 'obj.stub!(:message)'
            record.converted_syntax.should == 'allow(obj).to receive(:message)'
          end
        end

        context 'when it is `subject.stub(:method).and_return(value)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1' do
                  subject.stub(:foo).and_return(1)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1' do
                  allow(subject).to receive(:foo).and_return(1)
                end
              end
            END
          end

          it 'converts into `allow(subject).to receive(:method).and_return(value)` form' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `subject.stub(:method).and_raise(RuntimeError)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and raises RuntimeError' do
                  subject.stub(:foo).and_raise(RuntimeError)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and raises RuntimeError' do
                  allow(subject).to receive(:foo).and_raise(RuntimeError)
                end
              end
            END
          end

          it 'converts into `allow(subject).to receive(:method).and_raise(RuntimeError)` form' do
            rewritten_source.should == expected_source
          end
        end

        context 'when the statement continues over multi lines' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1' do
                  subject.stub(
                      :foo
                    ).
                    and_return(
                      1
                    )
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1' do
                  allow(subject).to receive(
                      :foo
                    ).
                    and_return(
                      1
                    )
                end
              end
            END
          end

          it 'keeps the style as far as possible' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `subject.stub(:method => value)` form' do
          context 'and #receive_messages is available' do
            # #before here does not work because #allowized! is invoked in super #before.
            let(:rspec_version) do
              rspec_version = Transpec.required_rspec_version
              rspec_version.stub(:receive_messages_available?).and_return(true)
              rspec_version
            end

            let(:source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo and returns 1' do
                    subject.stub(:foo => 1)
                  end
                end
              END
            end

            let(:expected_source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo and returns 1' do
                    allow(subject).to receive_messages(:foo => 1)
                  end
                end
              END
            end

            it 'converts into `allow(subject).to receive_messages(:method => value)` form' do
              rewritten_source.should == expected_source
            end

            it 'adds record ' +
               '`obj.stub(:message => value)` -> `allow(obj).to receive_messages(:message => value)`' do
              record.original_syntax.should  == 'obj.stub(:message => value)'
              record.converted_syntax.should == 'allow(obj).to receive_messages(:message => value)'
            end
          end

          context 'and #receive_messages is not available' do
            let(:source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo and returns 1' do
                    subject.stub(:foo => 1)
                  end
                end
              END
            end

            let(:expected_source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo and returns 1' do
                    allow(subject).to receive(:foo).and_return(1)
                  end
                end
              END
            end

            it 'converts into `allow(subject).to receive(:method).and_return(value)` form' do
              rewritten_source.should == expected_source
            end

            it 'adds record ' +
               '`obj.stub(:message => value)` -> `allow(obj).to receive(:message).and_return(value)`' do
              record.original_syntax.should  == 'obj.stub(:message => value)'
              record.converted_syntax.should == 'allow(obj).to receive(:message).and_return(value)'
            end
          end
        end

        context 'when it is `subject.stub(method: value)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1' do
                  subject.stub(foo: 1)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1' do
                  allow(subject).to receive(:foo).and_return(1)
                end
              end
            END
          end

          it 'converts into `allow(subject).to receive(:method).and_return(value)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record ' +
             '`obj.stub(:message => value)` -> `allow(obj).to receive(:message).and_return(value)`' do
            record.original_syntax.should  == 'obj.stub(:message => value)'
            record.converted_syntax.should == 'allow(obj).to receive(:message).and_return(value)'
          end
        end

        context 'when it is `subject.stub(:a_method => a_value, b_method => b_value)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1, and responds to #bar and returns 2' do
                  subject.stub(:foo => 1, :bar => 2)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo and returns 1, and responds to #bar and returns 2' do
                  allow(subject).to receive(:foo).and_return(1)
                  allow(subject).to receive(:bar).and_return(2)
                end
              end
            END
          end

          it 'converts into `allow(subject).to receive(:a_method).and_return(a_value)` ' +
             'and `allow(subject).to receive(:b_method).and_return(b_value)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record ' +
             '`obj.stub(:message => value)` -> `allow(obj).to receive(:message).and_return(value)`' do
            record.original_syntax.should  == 'obj.stub(:message => value)'
            record.converted_syntax.should == 'allow(obj).to receive(:message).and_return(value)'
          end

          context 'when the statement continues over multi lines' do
            context 'and #receive_messages is available' do
              # #before here does not work because #allowized! is invoked in super #before.
              let(:rspec_version) do
                rspec_version = Transpec.required_rspec_version
                rspec_version.stub(:receive_messages_available?).and_return(true)
                rspec_version
              end

              let(:source) do
                <<-END
                  describe 'example' do
                    it 'responds to #foo and returns 1, and responds to #bar and returns 2' do
                      subject
                        .stub(
                          :foo => 1,
                          :bar => 2
                        )
                    end
                  end
                END
              end

              let(:expected_source) do
                <<-END
                  describe 'example' do
                    it 'responds to #foo and returns 1, and responds to #bar and returns 2' do
                      allow(subject)
                        .to receive_messages(
                          :foo => 1,
                          :bar => 2
                        )
                    end
                  end
                END
              end

              it 'keeps the style' do
                rewritten_source.should == expected_source
              end
            end

            context 'and #receive_messages is not available' do
              let(:source) do
                <<-END
                  describe 'example' do
                    it 'responds to #foo and returns 1, and responds to #bar and returns 2' do
                      subject
                        .stub(
                          :foo => 1,
                          :bar => 2
                        )
                    end
                  end
                END
              end

              let(:expected_source) do
                <<-END
                  describe 'example' do
                    it 'responds to #foo and returns 1, and responds to #bar and returns 2' do
                      allow(subject)
                        .to receive(:foo).and_return(1)
                      allow(subject)
                        .to receive(:bar).and_return(2)
                    end
                  end
                END
              end

              it 'keeps the style except around the hash' do
                rewritten_source.should == expected_source
              end
            end
          end
        end

        context 'when it is `subject.stub_chain(:foo, :bar => value)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to .foo.bar and returns 1' do
                  subject.stub_chain(:foo, :bar => 1)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to .foo.bar and returns 1' do
                  allow(subject).to receive_message_chain(:foo, :bar => 1)
                end
              end
            END
          end

          context 'and #receive_message_chain is available' do
            # #before here does not work because #allowized! is invoked in super #before.
            let(:rspec_version) do
              rspec_version = Transpec.required_rspec_version
              rspec_version.stub(:receive_message_chain_available?).and_return(true)
              rspec_version
            end

            it 'converts into `allow(subject).to receive_message_chain(:foo, :bar => value)` form' do
              rewritten_source.should == expected_source
            end

            it "adds record `obj.stub_chain(:message1, :message2)` -> ' +
               '`allow(obj).to receive_message_chain(:message1, :message2)`" do
              record.original_syntax.should  == 'obj.stub_chain(:message1, :message2)'
              record.converted_syntax.should == 'allow(obj).to receive_message_chain(:message1, :message2)'
            end
          end

          context 'and #receive_message_chain is not available' do
            it 'does nothing' do
              rewritten_source.should == source
            end
          end
        end

        [:unstub, :unstub!].each do |method|
          context "when it is `subject.#{method}(:method)` form" do
            let(:source) do
              <<-END
                describe 'example' do
                  it 'does not respond to #foo' do
                    subject.#{method}(:foo)
                  end
                end
              END
            end

            it 'does nothing' do
              rewritten_source.should == source
            end

            it 'reports nothing' do
              method_stub_object.report.records.should be_empty
            end
          end
        end

        context 'when it is `Klass.any_instance.stub(:method)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  Klass.any_instance.stub(:foo)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  allow_any_instance_of(Klass).to receive(:foo)
                end
              end
            END
          end

          it 'converts into `allow_any_instance_of(Klass).to receive(:method)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record `Klass.any_instance.stub(:message)` ' +
             '-> `allow_any_instance_of(obj).to receive(:message)`' do
            record.original_syntax.should  == 'Klass.any_instance.stub(:message)'
            record.converted_syntax.should == 'allow_any_instance_of(Klass).to receive(:message)'
          end

          context 'when the statement continues over multi lines' do
            let(:source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo and returns 1' do
                    Klass
                      .any_instance
                        .stub(
                          :foo
                        ).
                        and_return(
                          1
                        )
                  end
                end
              END
            end

            let(:expected_source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo and returns 1' do
                    allow_any_instance_of(Klass)
                        .to receive(
                          :foo
                        ).
                        and_return(
                          1
                        )
                  end
                end
              END
            end

            it 'keeps the style as far as possible' do
              rewritten_source.should == expected_source
            end
          end
        end

        context 'when it is `described_class.any_instance.stub(:method)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  described_class.any_instance.stub(:foo)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  allow_any_instance_of(described_class).to receive(:foo)
                end
              end
            END
          end

          it 'converts into `allow_any_instance_of(described_class).to receive(:method)` form' do
            rewritten_source.should == expected_source
          end

          it 'adds record `Klass.any_instance.stub(:message)` ' +
             '-> `allow_any_instance_of(obj).to receive(:message)`' do
            record.original_syntax.should  == 'Klass.any_instance.stub(:message)'
            record.converted_syntax.should == 'allow_any_instance_of(Klass).to receive(:message)'
          end
        end

        context 'when it is `variable.any_instance.stub(:method)` form ' +
                'and the variable is an AnyInstance::Recorder' do
          context 'with runtime information' do
            include_context 'dynamic analysis objects'

            let(:source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo' do
                    variable = String.any_instance
                    variable.stub(:foo)
                  end
                end
              END
            end

            let(:expected_source) do
              <<-END
                describe 'example' do
                  it 'responds to #foo' do
                    variable = String.any_instance
                    allow_any_instance_of(String).to receive(:foo)
                  end
                end
              END
            end

            it 'converts into `allow_any_instance_of(Klass).to receive(:method)` form' do
              rewritten_source.should == expected_source
            end

            it 'adds record `Klass.any_instance.stub(:message)` ' +
               '-> `allow_any_instance_of(obj).to receive(:message)`' do
              record.original_syntax.should  == 'Klass.any_instance.stub(:message)'
              record.converted_syntax.should == 'allow_any_instance_of(Klass).to receive(:message)'
            end
          end
        end

        [:unstub, :unstub!].each do |method|
          context "when it is `Klass.any_instance.#{method}(:method)` form" do
            let(:source) do
              <<-END
                describe 'example' do
                  it 'does not respond to #foo' do
                    Klass.any_instance.#{method}(:foo)
                  end
                end
              END
            end

            it 'does nothing' do
              rewritten_source.should == source
            end

            it 'reports nothing' do
              method_stub_object.report.records.should be_empty
            end
          end
        end
      end

      describe '#convert_deprecated_method!' do
        before do
          method_stub_object.convert_deprecated_method!
        end

        [
          [:stub!,   :stub,   'responds to'],
          [:unstub!, :unstub, 'does not respond to']
        ].each do |method, replacement_method, description|
          context "when it is ##{method}" do
            let(:source) do
              <<-END
                describe 'example' do
                  it '#{description} #foo' do
                    subject.#{method}(:foo)
                  end
                end
              END
            end

            let(:expected_source) do
              <<-END
                describe 'example' do
                  it '#{description} #foo' do
                    subject.#{replacement_method}(:foo)
                  end
                end
              END
            end

            it "replaces with ##{replacement_method}" do
              rewritten_source.should == expected_source
            end

            it 'adds record ' +
               "`obj.#{method}(:message)` -> `obj.#{replacement_method}(:message)`" do
              record.original_syntax.should  == "obj.#{method}(:message)"
              record.converted_syntax.should == "obj.#{replacement_method}(:message)"
            end
          end
        end

        [
          [:stub,   'responds to'],
          [:unstub, 'does not respond to']
        ].each do |method, description|
          context "when it is ##{method}" do
            let(:source) do
              <<-END
                describe 'example' do
                  it '#{description} #foo' do
                    subject.#{method}(:foo)
                  end
                end
              END
            end

            it 'does nothing' do
              rewritten_source.should == source
            end

            it 'reports nothing' do
              method_stub_object.report.records.should be_empty
            end
          end
        end
      end

      describe '#allow_no_message?' do
        subject { method_stub_object.allow_no_message? }

        context 'when it is `subject.stub(:method).any_number_of_times` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo).any_number_of_times
                end
              end
            END
          end

          it { should be_true }
        end

        context 'when it is `subject.stub(:method).with(arg).any_number_of_times` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo with 1' do
                  subject.stub(:foo).with(1).any_number_of_times
                end
              end
            END
          end

          it { should be_true }
        end

        context 'when it is `subject.stub(:method).at_least(0)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo).at_least(0)
                end
              end
            END
          end

          it { should be_true }
        end

        context 'when it is `subject.stub(:method)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo)
                end
              end
            END
          end

          it { should be_false }
        end
      end

      describe '#remove_allowance_for_no_message!' do
        before do
          method_stub_object.remove_allowance_for_no_message!
        end

        context 'when it is `subject.stub(:method).any_number_of_times` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo).any_number_of_times
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo)
                end
              end
            END
          end

          it 'removes `.any_number_of_times`' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `subject.stub(:method).at_least(0)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo).at_least(0)
                end
              end
            END
          end

          let(:expected_source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo)
                end
              end
            END
          end

          it 'removes `.at_least(0)`' do
            rewritten_source.should == expected_source
          end
        end

        context 'when it is `subject.stub(:method)` form' do
          let(:source) do
            <<-END
              describe 'example' do
                it 'responds to #foo' do
                  subject.stub(:foo)
                end
              end
            END
          end

          it 'does nothing' do
            rewritten_source.should == source
          end
        end
      end
    end
  end
end
