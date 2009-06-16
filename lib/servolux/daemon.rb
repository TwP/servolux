
#
#
class Servolux::Daemon

  Error          = Class.new(StandardError)
  Timeout        = Class.new(Error)
  AlreadyStarted = Class.new(Error)

  attr_reader   :name
  attr_accessor :logger
  attr_accessor :pid_file
  attr_reader   :startup_command
  attr_accessor :shutdown_command
  attr_accessor :timeout
  attr_accessor :nochdir
  attr_accessor :noclose
  attr_reader   :log_file
  attr_reader   :look_for

  #
  #
  def initialize( opts = {} )
    self.server = opts[:server]

    @name = opts[:name] if opts.key?(:name)
    @logger = opts[:logger] if opts.key?(:logger)
    @pid_file = opts[:pid_file] if opts.key?(:pid_file)
    @startup_command = opts[:startup_command] if opts.key?(:startup_command)

    @timeout = opts.getopt(:timeout, 30)
    @nochdir = opts.getopt(:nochdir, false)
    @noclose = opts.getopt(:noclose, false)
    @shutdown_command = opts.getopt(:shutdown_command)

    @logfile_reader = nil
    self.log_file = opts.getopt(:log_file)
    self.look_for = opts.getopt(:look_for)

    yield self if block_given?

    ary = %w[name logger pid_file startup_command].map { |var|
      self.send(var).nil? ? var : nil
    }.compact
    raise Error, "These variables are required: #{ary.join(', ')}." unless ary.empty?
  end

  #
  #
  def startup_command=( val )
    @startup_command = val
    return unless val.is_a?(::Servolux::Server)

    @name = val.name
    @logger = val.logger
    @pid_file = val.pid_file
    @shutdown_command = nil
  end
  alias :server= :startup_command=
  alias :server  :startup_command

  #
  #
  def log_file=( filename )
    return if filename.nil?
    @logfile_reader ||= LogfileReader.new
    @logfile_reader.filename = filename
  end

  #
  #
  def look_for=( val )
    return if val.nil?
    @logfile_reader ||= LogfileReader.new
    @logfile_reader.look_for = val
  end

  # Start the Server either in the foreground or as a daemonized process.
  #
  def startup
    raise Error, "Fork is not supported in this Ruby environment." unless ::Servolux.fork?

    if alive?
      raise AlreadyStarted,
            "#{name.inspect} is already running: " \
            "PID is #{retrieve_pid} from PID file #{pid_file.inspect}"
    end

    daemonize
  end

  # Returns +true+ if the Maestro server is currently running. Returns
  # +false+ if this is not the case.
  #
  def alive?
    pid = retrieve_pid
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::ENOENT
    false
  rescue Errno::EACCES => err
    logger.error "You do not have access to the PID file at " \
                 "#{pid_file.inspect}: #{err.message}"
    false
  end

  # Send a signal to the server identified by the PID file. The default
  # signal to send is 'INT' (2). The signal can be given either as a
  # string or a signal number.
  #
  #   No |  Name     |   Default Action    |  Description
  #   ---+-----------+---------------------+------------------------------
  #   2     SIGINT       terminate process    interrupt program
  #   15    SIGTERM      terminate process    software termination signal
  #
  def kill( signal = 'INT' )
    signal = Signal.list.invert[signal] if signal.is_a?(Integer)
    pid = retrieve_pid
    logger.info "Killing PID #{pid} with #{signal}"
    Process.kill(signal, pid)
    wait_for_shutdown
  rescue Errno::EINVAL
    logger.error "Failed to kill PID #{pid} with #{signal}: " \
                 "'#{signal}' is an invalid or unsupported signal number."
  rescue Errno::EPERM
    logger.error "Failed to kill PID #{pid} with #{signal}: " \
                 "Insufficient permissions."
  rescue Errno::ESRCH
    logger.error "Failed to kill PID #{pid} with #{signal}: " \
                 "Process is deceased or zombie."
  rescue Errno::EACCES => err
    logger.error err.message
  rescue Errno::ENOENT => err
    logger.error "Could not find a PID file at #{pid_file.inspect}. " \
                 "Most likely the process is no longer running."
  rescue Exception => err
    unless err.is_a?(SystemExit)
      logger.error "Failed to kill PID #{pid} with #{signal}: #{err.message}"
    end
  end

  #
  #
  def logger
    @logger ||= Logging.logger[self]
  end

  private

  def daemonize
    logger.debug "About to fork ..."
    if fork                              # Parent process
      wait_for_startup
      logger.info 'Server has daemonized.'
      exit(0)
    else                                 # Child process
      Process.setsid                     # Become session leader.
      exit!(0) if fork                   # Zap session leader.

      Dir.chdir '/' unless nochdir       # Release old working directory.
      File.umask 0000                    # Ensure sensible umask.

      unless noclose
        STDIN.reopen  '/dev/null'        # Free file descriptors and
        STDOUT.reopen '/dev/null', 'a'   # point them somewhere sensible.
        STDERR.reopen '/dev/null', 'a'
      end

      run_startup_command
    end
  end

  def run_startup_command
    case startup_command
    when String; exec(startup_command)
    when Array; exec(*startup_command)
    when Proc, Method; startup_command.call
    when ::Servolux::Server; startup_command.startup
    else
      raise Error, "Unrecognized startup command #{startup_command.inspect}"
    end
  rescue Exception => err
    logger.fatal err unless err.is_a?(SystemExit)
  end

  def exec( *args )
    logger.debug "Calling: exec(*#{args.inspect})"
    std = [STDIN, STDOUT, STDERR]
    ObjectSpace.each_object(IO) { |obj|
      next if std.include? obj
      obj.close rescue nil
    }
    Kernel.exec(*args)
  end

  def retrieve_pid
    Integer(File.read(pid_file).strip)
  rescue TypeError
    raise Error, "A PID file was not specified."
  end

  def started?
    return false unless alive?
    return true if @logfile_reader.nil?
    @logfile_reader.updated?
  end

  def wait_for_startup
    logger.debug "Waiting for #{name.inspect} to startup."
    return if wait_for { started? }

    # if the daemon doesn't fork into the background in time, then kill it.
    pid = retrieve_pid

    t = Thread.new {
      begin
        sleep 7
        unless Thread.current[:stop]
          Process.kill('KILL', pid)
          Process.waitpid(pid)
        end
      rescue Exception
      end
    }

    Process.kill('TERM', pid) rescue nil
    Process.waitpid(pid) rescue nil
    t[:stop] = true
    t.run if t.status
    t.join

    raise Timeout, "#{name.inspect} failed to startup in a timely fashion. " \
                   "The timeout is set at #{timeout} seconds."

  rescue Errno::ENOENT
    raise Timeout, "Could not find a PID file at #{pid_file.inspect}."
  rescue Errno::EACCES => err
    raise Timeout, "You do not have access to the PID file at " \
                   "#{pid_file.inspect}: #{err.message}"
  end

  def wait_for_shutdown
    logger.debug "Waiting for #{name.inspect} to shutdown."
    return if wait_for { !alive? }
    raise Timeout, "#{name.inspect} failed to shutdown in a timely fashion. " \
                   "The timeout is set at #{timeout} seconds."
  end

  def wait_for
    start = Time.now
    nap_time = 0.1

    loop do
      sleep nap_time

      diff = Time.now - start
      nap_time = 2*nap_time
      nap_time = diff + 0.1 if diff < nap_time

      break true if yield
      break false if diff >= timeout
    end
  end

  class LogfileReader

    attr_accessor :filename
    attr_reader   :look_for

    def look_for=( val )
      case val
      when nil;    @look_for = nil
      when String; @look_for = Regexp.new(Regexp.escape(val))
      when Regexp; @look_for = val
      else
        raise Error,
              "Don't know how to look for #{val.inspect} in the logfile"
      end
    end

    def stat
      if @filename and test(?f, @filename)
        File.stat @filename
      end
    end

    def updated?
      s = stat
      @stat ||= s

      return false if s.nil?
      return false if @stat.mtime == s.mtime and @stat.size == s.size
      return true if @look_for.nil?

      File.open(@filename, 'r') do |fd|
        fd.seek @stat.size, IO::SEEK_SET
        while line = fd.gets
          return true if line =~ @look_for
        end
      end

      return false
    ensure
      @stat = s
    end

  end  # class LogfileReader

end  # class Servolux::Daemon

# EOF
