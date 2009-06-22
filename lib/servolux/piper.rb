
# == Synopsis
# A Piper is used to fork a child proces and then establish a communication
# pipe between the parent and child. This communication pipe is used to pass
# Ruby objects between the two.
#
# == Details
# When a new piper instance is created, the Ruby process is forked into two
# porcesses - the parent and the child. Each continues execution from the
# point of the fork. The piper establishes a pipe for communication between
# the parent and the child. This communication pipe can be opened as read /
# write / read-write (from the perspective of the parent).
#
# Communication over the pipe is handled by marshalling Ruby objects through
# the pipe. This means that nearly any Ruby object can be passed between the
# two processes. For example, exceptions from the child process can be
# marshalled back to the parent and raised there.
#
# Object passing is handled by use of the +puts+ and +gets+ methods defined
# on the Piper. These methods use a +timeout+ and the Kernel#select method
# to ensure a timely return.
#
# == Examples
#
#    piper = Servolux::Piper.new('r', :timeout => 5)
#
#    piper.parent {
#      $stdout.puts "parent pid #{Process.pid}"
#      $stdout.puts "child pid #{piper.pid} [from fork]"
#
#      child_pid = piper.gets
#      $stdout.puts "child pid #{child_pid} [from child]"
#
#      msg = piper.gets
#      $stdout.puts "message from child #{msg.inspect}"
#    }
#
#    piper.child {
#      sleep 2
#      piper.puts Process.pid
#      sleep 3
#      piper.puts "The time is #{Time.now}"
#    }
#
#    piper.close
#
class Servolux::Piper

  # :stopdoc:
  SEPERATOR = [0xDEAD, 0xBEEF].pack('n*').freeze
  # :startdoc:

  # call-seq:
  #    Piper.daemon( nochdir = false, noclose = false )
  #
  # Creates a new Piper with the child process configured as a daemon. The
  # +pid+ method of the piper returns the PID of the daemon process.
  #
  # Be default a daemon process will release its current working directory
  # and the stdout/stderr/stdin file descriptors. This allows the parent
  # process to exit cleanly. This behavior can be overridden by setting the
  # _nochdir_ and _noclose_ flags to true. The first will keep the current
  # working directory; the second will keep stdout/stderr/stdin open.
  #
  def self.daemon( nochdir = false, noclose = false )
    piper = self.new(:timeout => 1)
    piper.parent {
      pid = piper.gets
      piper.instance_variable_set(:@child_pid, pid)
    }
    piper.child {
      Process.setsid                     # Become session leader.
      exit!(0) if fork                   # Zap session leader.

      Dir.chdir '/' unless nochdir       # Release old working directory.
      File.umask 0000                    # Ensure sensible umask.

      unless noclose
        STDIN.reopen  '/dev/null'        # Free file descriptors and
        STDOUT.reopen '/dev/null', 'a'   # point them somewhere sensible.
        STDERR.reopen '/dev/null', 'a'
      end

      piper.puts Process.pid
    }
    return piper
  end

  # The timeout in seconds to wait for puts / gets commands.
  attr_accessor :timeout

  # The read end of the pipe.
  attr_reader :read_io

  # The write end of the pipe.
  attr_reader :write_io

  # call-seq:
  #    Piper.new( mode = 'r', opts = {} )
  #
  # Creates a new Piper instance with the communication pipe configured
  # using the provided _mode_. The default mode is read-only (from the
  # parent, and write-only from the child). The supported modes are as
  # follows:
  #
  #    Mode | Parent View | Child View
  #    -----+-------------+-----------
  #    r      read-only     write-only
  #    w      write-only    read-only
  #    rw     read-write    read-write
  #
  # The communication timeout can be provided as an option. This is the
  # number of seconds to wait for a +puts+ or +gets+ to succeed.
  #
  def initialize( *args )
    opts = args.last.is_a?(Hash) ? args.pop : {}
    mode = args.first || 'r'

    unless %w[r w rw].include? mode
      raise ArgumentError, "Unsupported mode #{mode.inspect}"
    end

    @timeout = opts.getopt(:timeout, 0)
    @read_io, @write_io = IO.pipe
    @child_pid = Kernel.fork

    if child?
      case mode
      when 'r'; close_read
      when 'w'; close_write
      end
    else
      case mode
      when 'r'; close_write
      when 'w'; close_read
      end
    end
  end

  # Close both the read and write ends of the communications pipe. This only
  # affects the process from which it was called -- the parent or the child.
  #
  def close
    @read_io.close rescue nil
    @write_io.close rescue nil
  end

  # Close the read end of the communications pipe. This only affects the
  # process from which it was called -- the parent or the child.
  #
  def close_read
    @read_io.close rescue nil
  end

  # Close the write end of the communications pipe. This only affects the
  # process from which it was called -- the parent or the child.
  #
  def close_write
    @write_io.close rescue nil
  end

  # Returns +true+ if the communications pipe is readable from the process
  # and there is data waiting to be read.
  #
  def readable?
    return false if @read_io.closed?
    r,w,e = Kernel.select([@read_io], nil, nil, @timeout)
    return !(r.nil? or r.empty?)
  end

  # Returns +true+ if the communications pipe is writeable from the process
  # and the write buffer can accept more data.
  #
  def writeable?
    return false if @write_io.closed?
    r,w,e = Kernel.select(nil, [@write_io], nil, @timeout)
    return !(w.nil? or w.empty?)
  end

  # call-seq:
  #    child { block }
  #    child {|piper| block }
  #
  # Execute the _block_ only in the child process. This method returns
  # immediately when called from the parent process.
  #
  def child( &block )
    return unless child?
    raise ArgumentError, "A block must be supplied" if block.nil?

    if block.arity > 0
      block.call(self)
    else
      block.call
    end
  end

  # Returns +true+ if this is the child prcoess and +false+ otherwise.
  #
  def child?
    @child_pid.nil?
  end

  # call-seq:
  #    parent { block }
  #    parent {|piper| block }
  #
  # Execute the _block_ only in the parent process. This method returns
  # immediately when called from the child process.
  #
  def parent( &block )
    return unless parent?
    raise ArgumentError, "A block must be supplied" if block.nil?

    if block.arity > 0
      block.call(self)
    else
      block.call
    end
  end

  # Returns +true+ if this is the parent prcoess and +false+ otherwise.
  #
  def parent?
    !@child_pid.nil?
  end

  # Returns the PID of the child process when called from the parent.
  # Returns +nil+ when called from the child.
  #
  def pid
    @child_pid
  end

  # Read an object from the communication pipe. Returns +nil+ if the pipe is
  # closed for reading or if no data is available before the timeout
  # expires. If data is available then it is un-marshalled and returned as a
  # Ruby object.
  #
  # This method will block until the +timeout+ is reached or data can be
  # read from the pipe.
  #
  def gets
    return unless readable?

    data = @read_io.gets SEPERATOR
    return if data.nil?

    data.chomp! SEPERATOR
    Marshal.load(data) rescue data
  end

  # Write an object to the communication pipe. Returns +nil+ if the pipe is
  # closed for writing or if the write buffer is full. The _obj_ is
  # marshalled and written to the pipe (therefore, procs and other
  # un-marshallable Ruby objects cannot be passed through the pipe).
  #
  # If the write is successful, then the number of bytes written to the pipe
  # is returned. If this number is zero it means that the _obj_ was
  # unsuccessfully communicated (sorry).
  #
  def puts( obj )
    return unless writeable?

    bytes = @write_io.write Marshal.dump(obj)
    @write_io.write SEPERATOR if bytes > 0
    @write_io.flush

    bytes
  end

  # Send the given signal to the child process. The signal may be an integer
  # signal number or a POSIX signal name (either with or without a +SIG+
  # prefix). 
  #
  # This method does nothing when called from the child process.
  #
  def signal( sig )
    return if @child_pid.nil?
    sig = Signal.list.invert[sig] if sig.is_a?(Integer)
    Process.kill(sig, @child_pid)
  end

end  # class Servolux::Piper

# EOF
