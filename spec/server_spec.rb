
require File.join(File.dirname(__FILE__), %w[spec_helper])

describe Servolux::Server do
  base = Class.new(Servolux::Server) do
    def initialize( &block )
      super('Test Server', :logger => Logging.logger['Servolux'], &block)
    end
    def run() sleep; end
  end

  before :each do
    @server = base.new
    File.delete @server.pid_file if test(?f, @server.pid_file)
  end

  after :each do
    File.delete @server.pid_file if test(?f, @server.pid_file)
  end

  it 'generates a PID file' do
    test(?e, @server.pid_file).should be_false

    t = Thread.new {@server.startup}
    Thread.pass until @server.status == 'sleep'
    test(?e, @server.pid_file).should be_true

    @server.shutdown
    Thread.pass until t.status == false
    test(?e, @server.pid_file).should be_false
  end

  it 'generates a PID file with mode rw-r----- by default' do
    t = Thread.new {@server.startup}
    Thread.pass until @server.status == 'sleep'
    (File.stat(@server.pid_file).mode & 0777).should == 0640
  end

  it 'generates PID file with the specified permissions' do
    @server.pid_file_mode = 0400
    t = Thread.new {@server.startup}
    Thread.pass until @server.status == 'sleep'
    (File.stat(@server.pid_file).mode & 0777).should == 0400
  end

  it 'shuts down gracefully when signaled' do
    t = Thread.new {@server.startup}
    Thread.pass until @server.status == 'sleep'
    @server.running?.should be_true

    Process.kill('INT', $$)
    Thread.pass until t.status == false
    @server.running?.should be_false
  end

  it 'responds to signals that have defined handlers' do
    class << @server
      def hup() logger.info 'hup was called'; end
      def usr1() logger.info 'usr1 was called'; end
      def usr2() logger.info 'usr2 was called'; end
    end

    t = Thread.new {@server.startup}
    Thread.pass until @server.status == 'sleep'
    @log_output.readline

    Process.kill('USR1', $$)
    @log_output.readline.strip.should == 'INFO  Servolux : usr1 was called'

    Process.kill('HUP', $$)
    @log_output.readline.strip.should == 'INFO  Servolux : hup was called'

    Process.kill('USR2', $$)
    @log_output.readline.strip.should == 'INFO  Servolux : usr2 was called'

    Process.kill('TERM', $$)
    Thread.pass until t.status == false
    @server.running?.should be_false
  end
end

# EOF
