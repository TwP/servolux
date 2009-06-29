
#
#
class Servolux::Child

  attr_accessor :command
  attr_accessor :timeout
  attr_accessor :signals
  attr_accessor :suspend
  attr_reader :io
  attr_reader :pid

  #
  #
  def initialize( command, opts = {} )
    @command = command
    @timeout = opts.getopt :timeout
    @signals = opts.getopt :signals, %w[TERM QUIT KILL]
    @suspend = opts.getopt :suspend, 4
    @io = @pid = @thread = @timed_out = nil
  end

  #
  #
  def start( mode = 'r', &block )
    start_timeout_thread if @timeout

    @io  = IO::popen @command, mode
    @pid = @io.pid

    return block.call(@io) unless block.nil?
    self
  end

  #
  #
  def stop
    unless @thread.nil?
      t, @thread = @thread, nil
      t[:stop] = true
      t.wakeup.join if t.status
    end

    kill if alive?
    @io.close rescue nil
    @io = @pid = nil
    self
  end

  # Waits for the child process to exit and returns its exit status. The
  # global variable $? is set to a Process::Status object containing
  # information on the child process.
  #
  def wait( flags = 0 )
    return if @io.nil?
    Process.wait(@pid, flags)
    $?.exitstatus
  end

  # Returns +true+ if the child process is alive.
  #
  def alive?
    return if @io.nil?
    Process.kill(0, @pid)
    true
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  # Returns +true+ if the child process was killed by the timeout thread.
  #
  def timed_out?
    @timed_out
  end


  private

  #
  #
  def kill
    return if @io.nil?

    existed = false
    @signals.each do |sig|
      begin
        Process.kill sig, @pid
        existed = true
      rescue Errno::ESRCH, Errno::ENOENT
        return(existed ? nil : true)
      end
      return true unless alive?
      sleep @suspend
      return true unless alive?
    end
    return !alive?
  end

  #
  #
  def start_timeout_thread
    @timed_out = false
    @thread = Thread.new(self) { |child|
      sleep @timeout
      unless Thread.current[:stop]
        if child.alive?
          child.instance_variable_set(:@timed_out, true)
          child.__send__(:kill)
        end
      end
    }
  end

end  # class Servolux::Child

# EOF
