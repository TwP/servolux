
require File.expand_path('../spec_helper', __FILE__)

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
    @server.shutdown
    File.delete @server.pid_file if test(?f, @server.pid_file)
  end

  it 'generates a PID file' do
    test(?e, @server.pid_file).should be_false

    t = Thread.new {@server.startup}
    Thread.pass until @server.running? and t.status == 'sleep'
    test(?e, @server.pid_file).should be_true

    @server.shutdown
    Thread.pass until t.status == false
    test(?e, @server.pid_file).should be_false
  end

  it 'generates a PID file with mode rw-r----- by default' do
    t = Thread.new {@server.startup}
    Thread.pass until @server.running? and t.status == 'sleep'
    test(?e, @server.pid_file).should be_true

    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Server "Test Server" creating pid file "test_server.pid")
    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Starting)
    (File.stat(@server.pid_file).mode & 0777).should be == 0640

    @server.shutdown
    Thread.pass until t.status == false
    test(?e, @server.pid_file).should be_false
  end

  it 'generates PID file with the specified permissions' do
    @server.pid_file_mode = 0400
    t = Thread.new {@server.startup}
    Thread.pass until @server.running? and t.status == 'sleep'
    test(?e, @server.pid_file).should be_true

    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Server "Test Server" creating pid file "test_server.pid")
    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Starting)
    (File.stat(@server.pid_file).mode & 0777).should be == 0400

    @server.shutdown
    Thread.pass until t.status == false
    test(?e, @server.pid_file).should be_false
  end

  it 'shuts down gracefully when signaled' do
    t = Thread.new {@server.startup}
STDERR.puts "server test #{__LINE__}"
    Thread.pass until @server.running? and t.status == 'sleep'
STDERR.puts "server test #{__LINE__}"
    @server.should be_running
STDERR.puts "server test #{__LINE__}"

    if ENV['TRAVIS']
STDERR.puts "server test #{__LINE__}"
      @server.int
    else
STDERR.puts "server test #{__LINE__}"
      Process.kill('INT', $$)
    end

STDERR.puts "server test #{__LINE__}"
    start = Time.now
STDERR.puts "server test #{__LINE__}"
    sleep 0.1 until t.status == false or (Time.now - start) > 5
STDERR.puts "server test #{__LINE__}"
    @server.should_not be_running
STDERR.puts "server test #{__LINE__}"
  end

  it 'responds to signals that have defined handlers' do
    class << @server
      def hup() logger.info 'hup was called'; end
      def usr1() logger.info 'usr1 was called'; end
      def usr2() logger.info 'usr2 was called'; end
    end

    t = Thread.new {@server.startup}
    Thread.pass until @server.running? and t.status == 'sleep'
    @log_output.readline

    Process.kill('USR1', $$)
    @log_output.readline.strip.should be == 'INFO  Servolux : usr1 was called'

    Process.kill('HUP', $$)
    @log_output.readline.strip.should be == 'INFO  Servolux : hup was called'

    Process.kill('USR2', $$)
    @log_output.readline.strip.should be == 'INFO  Servolux : usr2 was called'

    Process.kill('TERM', $$)
    start = Time.now
    sleep 0.1 until t.status == false or (Time.now - start) > 5
    @server.should_not be_running
  end
end

