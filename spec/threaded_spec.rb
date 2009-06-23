
require File.join(File.dirname(__FILE__), %w[spec_helper])

describe Servolux::Threaded do

  base = Class.new do
    include Servolux::Threaded
    def initialize
      @activity_thread_running = false
      @activity_thread_interval = 0
    end
    def pass( val = 'sleep' )
      Thread.pass until status == val
    end
  end

  it "let's you know that it is running" do
    klass = Class.new(base) do
      def run() sleep 1; end
    end

    obj = klass.new
    obj.interval = 0
    obj.running?.should be_false

    obj.start
    obj.running?.should be_true
    obj.pass

    obj.stop(2)
    obj.running?.should be_false
  end

  it "stops even when sleeping in the run method" do
    klass = Class.new(base) do
      attr_reader :stopped
      def run() sleep; end
      def after_starting() @stopped = false; end
      def after_stopping() @stopped = true; end
    end

    obj = klass.new
    obj.interval = 0
    obj.stopped.should be_nil

    obj.start
    obj.stopped.should be_false
    obj.pass

    obj.stop(2)
    obj.stopped.should be_true
  end

  it "calls all the before and after hooks" do
    klass = Class.new(base) do
      attr_accessor :ary
      def run() sleep 1; end
      def before_starting() ary << 1; end
      def after_starting() ary << 2; end
      def before_stopping() ary << 3; end
      def after_stopping() ary << 4; end
    end

    obj = klass.new
    obj.interval = 86400
    obj.ary = []

    obj.start
    obj.ary.should == [1,2]
    obj.pass

    obj.stop(2)
    obj.ary.should == [1,2,3,4]
  end

  it "dies when an exception is thrown" do
    klass = Class.new(base) do
      def run() raise 'ni'; end
    end

    obj = klass.new

    obj.start
    obj.pass nil

    obj.running?.should be_false
    @log_output.readline
    @log_output.readline.chomp.should == "FATAL  Object : <RuntimeError> ni"

    lambda { obj.join }.should raise_error(RuntimeError, 'ni')
  end

  it "complains loudly if you don't have a run method" do
    obj = base.new
    obj.start
    obj.pass nil

    @log_output.readline
    @log_output.readline.chomp.should == "FATAL  Object : <NotImplementedError> The run method must be defined by the threaded object."

    lambda { obj.join }.should raise_error(NotImplementedError, 'The run method must be defined by the threaded object.')
  end
end

# EOF
