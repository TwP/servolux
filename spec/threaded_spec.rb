
require File.join(File.dirname(__FILE__), %w[spec_helper])

describe Servolux::Threaded do

  base = Class.new do
    include Servolux::Threaded
    def initialize
      self.interval = 0
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
    obj.running?.should be_nil

    obj.start
    obj.running?.should be_true
    obj.pass

    obj.stop.join(2)
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

    obj.stop.join(2)
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

    obj.stop.join(2)
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

  it "lives if told to continue on error" do
    klass = Class.new(base) do
      def run()
        @sleep ||= false
        if @sleep then sleep
        else
          @sleep = true
          raise 'ni'
        end
      end
    end

    obj = klass.new
    obj.continue_on_error = true

    obj.start
    obj.pass

    obj.running?.should be_true
    @log_output.readline
    @log_output.readline.chomp.should == "ERROR  Object : <RuntimeError> ni"

    obj.stop.join(2)
    obj.running?.should be_false
  end

  it "complains loudly if you don't have a run method" do
    obj = base.new
    obj.start
    obj.pass nil

    @log_output.readline
    @log_output.readline.chomp.should == "FATAL  Object : <NotImplementedError> The run method must be defined by the threaded object."

    lambda { obj.join }.should raise_error(NotImplementedError, 'The run method must be defined by the threaded object.')
  end

  it "stops after a limited number of iterations" do
    klass = Class.new( base ) do
      def run() ; end
    end
    obj = klass.new
    obj.maximum_iterations = 5
    obj.iterations.should == 0
    obj.start
    obj.wait
    obj.iterations.should == 5
  end

  it "complains loudly if you attempt to set a maximum number of iterations < 1" do
    obj = base.new
    lambda { obj.maximum_iterations = -1 }.should raise_error( ArgumentError, "maximum iterations must be >= 1" )
  end
end

# EOF
