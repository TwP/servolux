
require File.join(File.dirname(__FILE__), %w[spec_helper])

if Servolux.fork?

describe Servolux::Piper do

  before :each do
    @piper = nil
  end

  after :each do
    next if @piper.nil?
    @piper.puts :die
    @piper.close
    @piper = nil
  end

  it 'only understands three file modes' do
    %w[r w rw].each do |mode|
      lambda {
        piper = Servolux::Piper.new(mode)
        piper.child { piper.close; exit! }
        piper.parent { piper.close }
      }.should_not raise_error
    end

    lambda { Servolux::Piper.new('f') }.should raise_error(
        ArgumentError, 'Unsupported mode "f"')
  end

  it 'enables communication between parents and children' do
    @piper = Servolux::Piper.new 'rw', :timeout => 2

    @piper.child {
      loop {
        obj = @piper.gets
        if :die == obj
          @piper.close; exit!
        end
        @piper.puts obj unless obj.nil?
      }
    }

    @piper.parent {
      @piper.puts 'foo bar baz'
      @piper.gets.should == 'foo bar baz'

      @piper.puts %w[one two three]
      @piper.gets.should == %w[one two three]

      @piper.puts('Returns # of bytes written').should > 0
      @piper.gets.should == 'Returns # of bytes written'

      @piper.puts 1
      @piper.puts 2
      @piper.puts 3
      @piper.gets.should == 1
      @piper.gets.should == 2
      @piper.gets.should == 3

      @piper.timeout = 0
      @piper.readable?.should be_false
    }
  end

  it 'sends signals from parent to child' do
    @piper = Servolux::Piper.new :timeout => 2

    @piper.child {
      Signal.trap('USR2') { @piper.puts "'USR2' was received" rescue nil }
      Signal.trap('INT') {
        @piper.puts "'INT' was received" rescue nil
        @piper.close
        exit!
      }
      Thread.new { sleep 7; exit! }
      @piper.puts :ready
      loop { sleep }
    }

    @piper.parent {
      @piper.gets.should == :ready

      @piper.signal 'USR2'
      @piper.gets.should == "'USR2' was received"

      @piper.signal 'INT'
      @piper.gets.should == "'INT' was received"
    }
  end

  it 'creates a daemon process' do
    @piper = Servolux::Piper.daemon(true, true)

    @piper.child {
      @piper.puts Process.ppid
      @piper.close
      exit!
    }

    @piper.parent {
      @piper.gets.should == 1
    }
  end

end
end  # if Servolux.fork?

# EOF
