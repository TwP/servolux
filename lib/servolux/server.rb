
# == Synopsis
# The Server class makes it simple to create a server-type application in
# Ruby. A server in this context is any process that should run for a long
# period of time either in the foreground or as a daemon.
#
# == Details
# The Server class provides for standard server features: process ID file
# management, signal handling, run loop, logging, etc. All that you need to
# provide is a +run+ method that will be called by the server's run loop.
# Optionally, you can provide a block to the +new+ method and it will be
# called within the run loop instead of a run method.
#
# SIGINT and SIGTERM are handled by default. These signals will gracefully
# shutdown the server by calling the +shutdown+ method (provided by default,
# too). A few other signals can be handled by defining a few methods on your
# server instance. For example, SIGINT is hanlded by the +int+ method (an
# alias for +shutdown+). Likewise, SIGTERM is handled by the +term+ method
# (another alias for +shutdown+). The following signal methods are
# recognized by the Server class:
#
#    Method  |  Signal  |  Default Action
#    --------+----------+----------------
#    hup        SIGHUP     none
#    int        SIGINT     shutdown
#    term       SIGTERM    shutdown
#    usr1       SIGUSR1    none
#    usr2       SIGUSR2    none
#
# In order to handle SIGUSR1 you would define a <tt>usr1</tt> method for your
# server.
#
# There are a few other methods that are useful and should be mentioned. Two
# methods are called before and after the run loop starts: +before_starting+
# and +after_starting+. The first is called just before the run loop thread
# is created and started. The second is called just after the run loop
# thread has been created (no guarantee is made that the run loop thread has
# actually been scheduled).
#
# Likewise, two other methods are called before and after the run loop is
# shutdown: +before_stopping+ and +after_stopping+. The first is called just
# before the run loop thread is signaled for shutdown. The second is called
# just after the run loop thread has died; the +after_stopping+ method is
# guarnteed to NOT be called till after the run loop thread is well and
# truly dead.
# 
# == Usage
# For simple, quick and dirty servers just pass a block to the Server
# initializer. This block will be used as the run method.
#
#    server = Servolux::Server.new('Basic', :interval => 1) {
#      puts "I'm alive and well @ #{Time.now}"
#    }
#    server.startup
#
# For more complex services you will need to define your own server methods:
# the +run+ method, signal handlers, and before/after methods. Any pattern
# that Ruby provides for defining methods on objects can be used to define
# these methods. In a nutshell:
#
# Inheritance
#
#    class MyServer < Servolux::Server
#      def run
#        puts "I'm alive and well @ #{Time.now}"
#      end
#    end
#    server = MyServer.new('MyServer', :interval => 1)
#    server.startup
#
# Extension
#
#    module MyServer
#      def run
#        puts "I'm alive and well @ #{Time.now}"
#      end
#    end
#    server = Servolux::Server.new('Module', :interval => 1)
#    server.extend MyServer
#    server.startup
#
# Singleton Class
#
#    server = Servolux::Server.new('Singleton', :interval => 1)
#    class << server
#      def run
#        puts "I'm alive and well @ #{Time.now}"
#      end
#    end
#    server.startup
#
# == Examples
#
# === Signals
# This example shows how to change the log level of the server when SIGUSR1
# is sent to the process. The log level toggles between "debug" and the
# original log level each time SIGUSR1 is sent to the server process. Since
# this is a module, it can be used with any Servolux::Server instance.
#
#    module DebugSignal
#      def usr1
#        @old_log_level ||= nil
#        if @old_log_level
#          logger.level = @old_log_level
#          @old_log_level = nil
#        else
#          @old_log_level = logger.level
#          logger.level = :debug
#        end
#      end
#    end
#
#    server = Servolux::Server.new('Debugger', :interval => 2) {
#      logger.info "Running @ #{Time.now}"
#      logger.debug "hey look - a debug message"
#    }
#    server.extend DebugSignal
#    server.startup
#
class Servolux::Server
  include ::Servolux::Threaded

  # :stopdoc:
  SIGNALS = %w[HUP INT TERM USR1 USR2] & Signal.list.keys
  SIGNALS.each {|sig| sig.freeze}.freeze
  # :startdoc:

  Error = Class.new(::Servolux::Error)

  attr_reader   :name
  attr_accessor :logger
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
    @activity_thread_running = false

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
