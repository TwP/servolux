
require File.join(File.dirname(__FILE__), %w[spec_helper])

describe Servolux::Child do

  before :all do
    @child = Servolux::Child.new
  end

  after :each do
    @child.stop
  end

  it 'has some sensible defaults' do
    @child.command.should be_nil
    @child.timeout.should be_nil
    @child.signals.should == %w[TERM QUIT KILL]
    @child.suspend.should == 4
    @child.pid.should be_nil
    @child.io.should be_nil
  end

  it 'starts a child process' do
    @child.command = 'echo `pwd`'
    @child.start

    @child.pid.should_not be_nil
    @child.wait
    @child.io.read.strip.should == Dir.pwd
    @child.success?.should be_true
  end

  it 'kills a child process after some timeout' do
    @child.command = 'sleep 5; echo `pwd`'
    @child.timeout = 0.25
    @child.start

    @child.pid.should_not be_nil
    @child.wait

    @child.io.read.strip.should be_empty

    @child.signaled?.should be_true
    @child.exited?.should be_false
    @child.exitstatus.should be_nil
    @child.success?.should be_nil
  end

end

# EOF
