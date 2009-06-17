
class Servolux::Piper

  SEPERATOR = [0xDEAD, 0xBEEF].pack('n*').freeze    # :nodoc:

  def self.daemon( nochdir = false, noclose = false )
    piper = self.new('r', :timeout => 1)
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
    piper
  end

  attr_accessor :timeout
  attr_reader :read_io
  attr_reader :write_io

  def initialize( mode = 'r', opts = {} )
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

  def close
    @read_io.close rescue nil
    @write_io.close rescue nil
  end

  def close_read
    @read_io.close rescue nil
  end

  def close_write
    @write_io.close rescue nil
  end

  def readable?
    return false if @read_io.closed?
    r,w,e = Kernel.select([@read_io], nil, nil, @timeout)
    return !(r.nil? or r.empty?)
  end

  def writeable?
    return false if @write_io.closed?
    r,w,e = Kernel.select(nil, [@write_io], nil, @timeout)
    return !(w.nil? or w.empty?)
  end

  def child( &block )
    return unless child?
    raise ArgumentError, "A block must be supplied" if block.nil?

    if block.arity > 0
      block.call(self)
    else
      block.call
    end
  end

  def child?
    @child_pid.nil?
  end

  def parent( &block )
    return unless parent?
    raise ArgumentError, "A block must be supplied" if block.nil?

    if block.arity > 0
      block.call(self)
    else
      block.call
    end
  end

  def parent?
    !@child_pid.nil?
  end

  def pid
    @child_pid
  end

  def gets
    return unless readable?

    data = @read_io.gets SEPERATOR
    return if data.nil?

    data.chomp! SEPERATOR
    Marshal.load(data) rescue data
  end

  def puts( obj )
    return unless writeable?

    bytes = 0
    if obj.is_a? String
      bytes += @write_io.write obj
    else
      bytes += @write_io.write Marshal.dump(obj)
    end
    @write_io.write SEPERATOR if bytes > 0
    @write_io.flush

    bytes
  end

end  # class Servolux::Piper

# EOF
