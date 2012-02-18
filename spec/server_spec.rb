
require File.expand_path('../spec_helper', __FILE__)

describe Servolux::Server do

  def wait_until( seconds = 5 )
    start = Time.now
    sleep 0.250 until (Time.now - start) > seconds or yield
  end

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
    wait_until { @server.running? and t.status == 'sleep' }
    test(?e, @server.pid_file).should be_true

    @server.shutdown
    wait_until { t.status == false }
    test(?e, @server.pid_file).should be_false
  end

  it 'generates a PID file with mode rw-r----- by default' do
    t = Thread.new {@server.startup}
    wait_until { @server.running? and t.status == 'sleep' }
    test(?e, @server.pid_file).should be_true

    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Server "Test Server" creating pid file "test_server.pid")
    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Starting)
    (File.stat(@server.pid_file).mode & 0777).should be == 0640

    @server.shutdown
    wait_until { t.status == false }
    test(?e, @server.pid_file).should be_false
  end

  it 'generates PID file with the specified permissions' do
    @server.pid_file_mode = 0400
    t = Thread.new {@server.startup}
    wait_until { @server.running? and t.status == 'sleep' }
    test(?e, @server.pid_file).should be_true

    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Server "Test Server" creating pid file "test_server.pid")
    @log_output.readline.chomp.should be == %q(DEBUG  Servolux : Starting)
    (File.stat(@server.pid_file).mode & 0777).should be == 0400

    @server.shutdown
    wait_until { t.status == false }
    test(?e, @server.pid_file).should be_false
  end

  it 'shuts down gracefully when signaled' do
    t = Thread.new {@server.startup}
    wait_until { @server.running? and t.status == 'sleep' }
    @server.should be_running

    Process.kill 'SIGINT', $$
    wait_until { t.status == false }
    @server.should_not be_running
  end

  it 'responds to signals that have defined handlers' do
    class << @server
      def hup() logger.info 'hup was called'; end
      def usr1() logger.info 'usr1 was called'; end
      def usr2() logger.info 'usr2 was called'; end
    end

    t = Thread.new {@server.startup}
    wait_until { @server.running? and t.status == 'sleep' }
    @log_output.readline
    @log_output.readline.strip.should be == 'DEBUG  Servolux : Starting'

    line = nil
    Process.kill 'SIGUSR1', $$
    wait_until { line = @log_output.readline }
    line.should_not be_nil
    line.strip.should be == 'INFO  Servolux : usr1 was called'

    line = nil
    Process.kill 'SIGHUP', $$
    wait_until { line = @log_output.readline }
    line.should_not be_nil
    line.strip.should be == 'INFO  Servolux : hup was called'

    line = nil
    Process.kill 'SIGUSR2', $$
    wait_until { line = @log_output.readline }
    line.should_not be_nil
    line.strip.should be == 'INFO  Servolux : usr2 was called'

    Process.kill 'SIGTERM', $$
    wait_until { t.status == false }
    @server.should_not be_running
  end
end

