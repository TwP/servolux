# == Synopsis
# The Daemon takes care of the work of creating and managing daemon
# processes from Ruby.
#
# == Details
# A daemon process is a long running process on a UNIX system that is
# detached from a TTY -- i.e. it is not tied to a user session. These types
# of processes are notoriously difficult to setup correctly. This Daemon
# class encapsulates some best practices to ensure daemons startup properly
# and can be shutdown gracefully.
#
# Starting a daemon process involves forking a child process, setting the
# child as a session leader, forking again, and detaching from the current
# working directory and standard in/out/error file descriptors. Because of
# this separation between the parent process and the daemon process, it is
# difficult to know if the daemon started properly.
#
# The Daemon class opens a pipe between the parent and the daemon. The PID
# of the daemon is sent to the parent through this pipe. The PID is used to
# check if the daemon is alive. Along with the PID, any errors from the
# daemon process are marshalled through the pipe back to the parent. These
# errors are wrapped in a StartupError and then raised in the parent.
#
# If no errors are passed up the pipe, the parent process waits till the
# daemon starts. This is determined by sending a signal to the daemon
# process.
#
# If a log file is given to the Daemon instance, then it is monitored for a
# change in size and mtime. This lets the Daemon instance know that the
# daemon process is updating the log file. Furthermore, the log file can be
# watched for a specific pattern; this pattern signals that the daemon
# process is up and running.
#
# Shutting down the daemon process is a little simpler. An external shutdown
# command can be used, or the Daemon instance will send an INT or TERM
# signal to the daemon process.
#
# Again, the Daemon instance will wait till the daemon process shuts down.
# This is determined by attempting to signal the daemon process PID and then
# returning when this signal fails -- i.e. then the deamon process has died.
#
# == Examples
#
# ==== Bad Example
# This is a bad example. The daemon will not start because the startup
# command "/usr/bin/no-command-by-this-name" cannot be found on the file
# system. The daemon process will send an Errno::ENOENT through the pipe
# back to the parent which gets wrapped in a StartupError
#
#    daemon = Servolux::Daemon.new(
#        :name => 'Bad Example',
#        :pid_file => '/dev/null',
#        :startup_command => '/usr/bin/no-command-by-this-name'
#    )
#    daemon.startup    #=> raises StartupError
#
# ==== Good Example
# This is a simple Ruby server that prints the time to a file every minute.
# So, it's not really a "good" example, but it will work.
#
#    server = Servolux::Server.new('TimeStamp', :interval => 60)
#    class << server
#      def file() @fd ||= File.open('timestamps.txt', 'w'); end
#      def run() file.puts Time.now; end
#    end
#
#    daemon = Servolux::Daemon.new(:server => server, :log_file => 'timestamps.txt')
#    daemon.startup
#
class Servolux::Daemon

  Error = Class.new(::Servolux::Error)
  Timeout = Class.new(Error)
  StartupError = Class.new(Error)

  attr_reader   :name
  attr_writer   :logger
  attr_accessor :pid_file
  attr_reader   :startup_command
  attr_accessor :shutdown_command
  attr_accessor :timeout
  attr_accessor :nochdir
  attr_accessor :noclose
  attr_reader   :log_file
  attr_reader   :look_for

  # Create a new Daemon that will manage the +startup_command+ as a deamon
  # process.
  #
  # ==== Required
  # * name <String>
  #     The name of the daemon process. This name will appear in log
  #     messages.
  #  
  # * logger <Logger>
  #     The Logger instance used to output messages.
  #
  # * pid_file <String>
  #     Location of the PID file. This is used to determine if the daemon
  #     process is running, and to send signals to the daemon process.
  #
  # * startup_command
  #     Assign the startup command. This can be either a String, an Array of
  #     strings, a Proc, a bound Method, or a Servolux::Server instance.
  #     Different calling semantics are used for each type of command. See
  #     the setter method for more details.
  #
  # ==== Options
  #
  # * timeout <Numeric>
  #     The time (in seconds) to wait for the daemon process to either
  #     startup or shutdown. An error is raised when this timeout is
  #     exceeded. The default is 30 seconds.
  #
  # * nochdir <Boolean>
  #     When set to true this flag directs the daemon process to keep the
  #     current working directory. By default, the process of daemonizing
  #     will cause the current working directory to be changed to the root
  #     folder (thus preventing the daemon process from holding onto the
  #     directory inode). The default is false.
  #
  # * noclose <Boolean>
  #     When set to true this flag keeps the standard input/output streams
  #     from being reopend to /dev/null when the deamon process is created.
  #     Reopening the standard input/output streams frees the file
  #     descriptors which are still being used by the parent process. This
  #     prevents zombie processes. The default is false.
  #
  # * shutdown_command
  #     Assign the startup command. This can be either a String, an Array of
  #     strings, a Proc, a bound Method, or a Servolux::Server instance.
  #     Different calling semantics are used for each type of command.
  #
  # * log_file <String>
  #     This log file will be monitored to determine if the daemon process
  #     has sucessfully started.
  #
  # * look_for
  #     This can be either a String or a Regexp. It defines a phrase to
  #     search for in the log_file. When the daemon process is started, the
  #     parent process will not return until this phrase is found in the log
  #     file. This is a useful check for determining if the daemon process
  #     is fully started. The default is nil.
  #
  def initialize( opts = {} )
    self.server = opts.getopt(:server) || opts.getopt(:startup_command)

    @name     = opts[:name]     if opts.key?(:name)
    @logger   = opts[:logger]   if opts.key?(:logger)
    @pid_file = opts[:pid_file] if opts.key?(:pid_file)
    @timeout  = opts.getopt(:timeout, 30)
    @nochdir  = opts.getopt(:nochdir, false)
    @noclose  = opts.getopt(:noclose, false)
    @shutdown_command = opts.getopt(:shutdown_command)

    @piper = nil
    @logfile_reader = nil
    self.log_file = opts.getopt(:log_file)
    self.look_for = opts.getopt(:look_for)

    yield self if block_given?

    ary = %w[name logger pid_file startup_command].map { |var|
      self.send(var).nil? ? var : nil
    }.compact
    raise Error, "These variables are required: #{ary.join(', ')}." unless ary.empty?
  end

  # Assign the startup command. This can be either a String, an Array of
  # strings, a Proc, a bound Method, or a Servolux::Server instance.
  # Different calling semantics are used for each type of command.
  #
  # If the startup command is a String or an Array of strings, then
  # Kernel#exec is used to run the command. Therefore, the string (or array)
  # should be system level command that is either fully qualified or can be
  # found on the current environment path.
  #
  # If the startup command is a Proc or a bound Method then it is invoked
  # using the +call+ method on the object. No arguments are passed to the
  # +call+ invocoation.
  #
  # Lastly, if the startup command is a Servolux::Server then it's +startup+
  # method is called.
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

  # Assign the log file name. This log file will be monitored to determine
  # if the daemon process is running.
  #
  def log_file=( filename )
    return if filename.nil?
    @logfile_reader ||= LogfileReader.new
    @logfile_reader.filename = filename
  end

  # A string or regular expression to search for in the log file. When the
  # daemon process is started, the parent process will not return until this
  # phrase is found in the log file. This is a useful check for determining
  # if the daemon process is fully started.
  #
  # If no phrase is given to look for, then the log file will simply be
  # watched for a change in size and a modified timestamp.
  #
  def look_for=( val )
    return if val.nil?
    @logfile_reader ||= LogfileReader.new
    @logfile_reader.look_for = val
  end

  # Start the daemon process.
  #
  def startup
    raise Error, "Fork is not supported in this Ruby environment." unless ::Servolux.fork?
    return if alive?

    logger.debug "About to fork ..."
    @piper = ::Servolux::Piper.daemon(nochdir, noclose)

    @piper.parent {
      @piper.timeout = 0
      wait_for_startup
      exit!(0)
    }

    @piper.child { run_startup_command }
  end

  # Stop the daemon process. If a shutdown command has been defined, it will
  # be called to stop the daemon process. Otherwise, SIGINT will be sent to
  # the daemon process to terminate it.
  #
  def shutdown
    return unless alive?

    case shutdown_command
    when nil; kill
    when String; exec(shutdown_command)
    when Array; exec(*shutdown_command)
    when Proc, Method; shutdown_command.call
    when ::Servolux::Server; shutdown_command.shutdown
    else
      raise Error, "Unrecognized shutdown command #{shutdown_command.inspect}"
    end

    wait_for_shutdown
  end

  # Returns +true+ if the daemon processis currently running. Returns
  # +false+ if this is not the case. The status of the process is determined
  # by sending a signal to the process identified by the +pid_file+.
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

  # Send a signal to the daemon process identified by the PID file. The
  # default signal to send is 'INT' (2). The signal can be given either as a
  # string or a signal number.
  #
  def kill( signal = 'INT' )
    signal = Signal.list.invert[signal] if signal.is_a?(Integer)
    pid = retrieve_pid
    logger.info "Killing PID #{pid} with #{signal}"
    Process.kill(signal, pid)
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

  # Returns the logger instance used by the daemon to log messages.
  #
  def logger
    @logger ||= Logging.logger[self]
  end


  private

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
    unless err.is_a?(SystemExit)
      logger.fatal err
      @piper.puts err
    end
  ensure
    @piper.close
  end

  def exec( *args )
    logger.debug "Calling: exec(*#{args.inspect})"
    skip = [STDIN, STDOUT, STDERR]
    skip << @piper.write_io if @piper
    ObjectSpace.each_object(IO) { |obj|
      next if skip.include? obj
      obj.close rescue nil
    }
    Kernel.exec(*args)
  end

  def retrieve_pid
    @piper ? @piper.pid : Integer(File.read(pid_file).strip)
  rescue TypeError
    raise Error, "A PID file was not specified."
  rescue ArgumentError
    raise Error, "#{pid_file.inspect} does not contain a valid PID."
  end

  def started?
    return false unless alive?
    return true if @logfile_reader.nil?
    @logfile_reader.updated?
  end

  def wait_for_startup
    logger.debug "Waiting for #{name.inspect} to startup."

    started = wait_for {
      rv = started?
      err = @piper.gets
      raise StartupError, "Child raised error: #{err.inspect}" unless err.nil?
      rv
    }

    raise Timeout, "#{name.inspect} failed to startup in a timely fashion. " \
                   "The timeout is set at #{timeout} seconds." unless started

    logger.info 'Server has daemonized.'
  ensure
    @piper.close
  end

  def wait_for_shutdown
    logger.debug "Waiting for #{name.inspect} to shutdown."
    return if wait_for { !alive? }
    raise Timeout, "#{name.inspect} failed to shutdown in a timely fashion. " \
                   "The timeout is set at #{timeout} seconds."
  end

  def wait_for
    start = Time.now
    nap_time = 0.2

    loop do
      sleep nap_time

      diff = Time.now - start
      nap_time = 2*nap_time
      nap_time = 0.2 if nap_time > 1.6

      break true if yield
      break false if diff >= timeout
    end
  end

  # :stopdoc:
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
  # :startdoc:

end  # class Servolux::Daemon

# EOF
