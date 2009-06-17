
# The Server class makes it simple to create a server-type application in
# Ruby. A server in this context is any process that should run for a long
# period of time either in the foreground or as a daemon process.
#
# Use by inheritance.
#
# Use by extending.
#
# Use by block/proc.
#
# Use by class << self.
#
# Handling signals.
#
class Servolux::Server
  include ::Servolux::Threaded

  # :stopdoc:
  SIGNALS = %w[HUP INT TERM USR1 USR2] & Signal.list.keys
  SIGNALS.each {|sig| sig.freeze}.freeze
  # :startdoc:

  Error = Class.new(::Servolux::Error)

  attr_reader   :name
  attr_writer   :logger
  attr_writer   :pid_file

  # call-seq:
  #    Server.new( name, options = {} ) { block }
  #
  # Creates a new server identified by _name_ and configured from the
  # _options_ hash. The _block_ is run inside a separate thread that will
  # loop at the configured interval.
  #
  # ==== Options
  # * logger <Logger> :: The logger instance this server will use
  # * pid_file <String> :: Location of the PID file
  # * interval <Numeric> :: Sleep interval between invocations of the _block_
  #
  def initialize( name, opts = {}, &block )
    @name = name

    self.logger   = opts.getopt :logger
    self.pid_file = opts.getopt :pid_file
    self.interval = opts.getopt :interval, 0

    if block
      eg = class << self; self; end
      eg.__send__(:define_method, :run, &block)
    end

    ary = %w[name logger pid_file].map { |var|
      self.send(var).nil? ? var : nil
    }.compact
    raise Error, "These variables are required: #{ary.join(', ')}." unless ary.empty?
  end

  # Start the server running using it's own internal thread. This method
  # will not return until the server is shutdown.
  #
  # Startup involves creating a PID file, registering signal handlers to
  # shutdown the server, starting and joining the server thread. The PID
  # file is deleted when this method returns.
  #
  def startup
    return self if running?
    begin
      create_pid_file
      trap_signals
      start
      join
    ensure
      delete_pid_file
    end
    return self
  end

  alias :shutdown :stop     # for symmetry with the startup method
  alias :int :stop          # handles the INT signal
  alias :term :stop         # handles the TERM signal
  private :start, :stop

  # Returns the logger instance used by the server. If none was given, then
  # a logger is created from the Logging framework (see the Logging rubygem
  # for more information).
  #
  def logger
    @logger ||= Logging.logger[self]
  end

  # Returns the PID file name used by the server. If none was given, then
  # the server name is used to create a PID file name.
  #
  def pid_file
    @pid_file ||= name.downcase.tr(' ','_') + '.pid'
  end

  private

  def create_pid_file
    logger.debug "Server #{name.inspect} creating pid file #{pid_file.inspect}"
    File.open(pid_file, 'w') {|fd| fd.write(Process.pid.to_s)}
  end

  def delete_pid_file
    if test(?f, pid_file)
      logger.debug "Server #{name.inspect} removing pid file #{pid_file.inspect}"
      File.delete(pid_file)
    end
  end

  def trap_signals
    SIGNALS.each do |sig|
      m = sig.downcase.to_sym
      Signal.trap(sig) { self.send(m) rescue nil } if self.respond_to? m
    end
  end

end  # class Servolux::Server

# EOF
