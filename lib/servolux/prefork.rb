
# == Synopsis
# The Prefork class provides a pre-forking worker pool for executing tasks in
# parallel using multiple processes.
#
# == Details
# A pre-forking worker pool is a technique for executing code in parallel in a
# UNIX environment. Each worker in the pool forks a child process and then
# executes user supplied code in that child process. The child process can
# pull jobs from a queue (beanstalkd for example) or listen on a socket for
# network requests.
#
# The code to execute in the child processes is passed as a block to the
# Prefork initialize method. The child processes executes this code in a loop;
# that is, your code block should not worry about keeping itself alive. This
# is handled by the library.
#
# If your code raises an exception, it will be captured by the library code
# and marshalled back to the parent process. This will halt the child process.
# The Prefork worker pool does not restart dead workers. A method is provided
# to iterate over workers that have errors, and it is up to the user to handle
# errors as they please.
#
# Instead of passing a block to the initialize method, you can provide a Ruby
# module that defines an "execute" method. This method will be executed in the
# child process' run loop. When using a module, you also have the option of
# defining a "before_executing" method and an "after_executing" method. These
# methods will be called before the child starts the execute loop and after
# the execute loop finishes. Each method will be called exactly once. Both
# methods are optional.
#
# Sending a SIGHUP to a child process will cause that child to stop and
# restart. The child will send a signal to the parent asking to be shutdown.
# The parent will gracefully halt the child and then start a new child process
# to replace it.
#
# This has the advantage of calling your before/after_executing methods again
# and reloading any code or resources your worker code will use. The SIGHUP
# will call Thread#wakeup on the main child process thread; please write your
# code to respond accordingly to this wakeup call (a thread waiting on a
# Queue#pop will not return when wakeup is called on the thread).
#
# == Examples
#
# A pre-forking echo server: http://github.com/TwP/servolux/blob/master/examples/echo.rb
#
# Pulling jobs from a beanstalkd work queue: http://github.com/TwP/servolux/blob/master/examples/beanstalk.rb
#
# ==== Before / After Executing
# In this example, we are creating 42 worker processes that will log the
# process ID and the current time to a file. Each worker will do this every 2
# seconds. The before/after_executing methods are used to open the file before
# the run loop starts and to close the file after the run loop completes. The
# execute method uses the stored file descriptor when logging the message.
#
#    module RunMe
#      def before_executing
#        @fd = File.open("#{Process.pid}.txt", 'w')
#      end
#
#      def after_executing
#        @fd.close
#      end
#
#      def execute
#        @fd.puts "Process #{Process.pid} @ #{Time.now}"
#        sleep 2
#      end
#    end
#
#    pool = Servolux::Prefork.new(:module => RunMe)
#    pool.start 42
#
# ==== Heartbeat
# When a :timeout is supplied to the constructor, a "heartbeat" is setup
# between the parent and the child worker. Each loop through the child's
# execute code must return before :timeout seconds have elapsed. If one
# iteration through the loop takes longer than :timeout seconds, then the
# parent process will halt the child worker. An error will be raised in the
# parent process.
#
#    pool = Servolux::Prefork.new(:timeout => 2) {
#      puts "Process #{Process.pid} is running."
#      sleep(rand * 5)
#    }
#    pool.start 42
#
# Eventually all 42 child processes will be killed by their parents. The
# random number generator will eventually cause the child to sleep longer than
# two seconds.
#
# What is happening here is that each time the child processes executes the
# block of code, the Servolux library code will send a "heartbeat" message to
# the parent. The parent is using a Kernel#select call on the communications
# pipe to wait for this message. The timeout is passed to the select call, and
# this will cause it to return +nil+ -- this is the error condition the
# heartbeat prevents.
#
# Use the heartbeat with caution -- allow margins for timing issues and
# processor load spikes.
#
class Servolux::Prefork

  Timeout = Class.new(::Servolux::Error)
  UnknownSignal = Class.new(::Servolux::Error)
  UnknownResponse = Class.new(::Servolux::Error)

  # :stopdoc:
  START = "\000START".freeze
  HALT = "\000HALT".freeze
  ERROR = "\000SHIT".freeze
  HEARTBEAT = "\000<3".freeze
  # :startdoc:

  attr_accessor :timeout    # Communication timeout in seconds.

  # call-seq:
  #    Prefork.new { block }
  #    Prefork.new( :module => Module )
  #
  # Create a new pre-forking worker pool. You must provide a block of code for
  # the workers to execute in their child processes. This code block can be
  # passed either as a block to this method or as a module via the :module
  # option.
  #
  # If a :timeout is given, then each worker will setup a "heartbeat" between
  # the parent process and the child process. If the child does not respond to
  # the parent within :timeout seconds, then the child process will be halted.
  # If you do not want to use the heartbeat then leave the :timeout unset or
  # manually set it to +nil+.
  #
  # The pre-forking worker pool makes no effort to restart dead workers. It is
  # left to the user to implement this functionality.
  #
  def initialize( opts = {}, &block )
    @timeout = opts[:timeout]
    @module = opts[:module]
    @module = Module.new { define_method :execute, &block } if block
    @workers = []

    raise ArgumentError, 'No code was given to execute by the workers.' unless @module
  end

  # Start up the given _number_ of workers. Each worker will create a child
  # process and run the user supplied code in that child process.
  #
  def start( number )
    @workers.clear

    number.times {
      @workers << Worker.new(self)
      @workers.last.extend @module
    }
    @workers.each { |worker| worker.start }
    self
  end

  # Stop all workers. The current process will wait for each child process to
  # exit before this method will return. The worker instances are not
  # destroyed by this method; this means that the +each_worker+ and the
  # +errors+ methods will still function correctly after stopping the workers.
  #
  def stop
    @workers.each { |worker| worker.stop }
    @workers.each { |worker| worker.wait }
    self
  end

  # call-seq:
  #    each_worker { |worker| block }
  #
  # Iterates over all the works and yields each, in turn, to the given
  # _block_.
  #
  def each_worker( &block )
    @workers.each(&block)
    self
  end

  # call-seq:
  #    errors { |worker| block }
  #
  # Iterates over all the works and yields the worker to the given _block_
  # only if the worker has an error condition.
  #
  def errors
    @workers.each { |worker| yield worker unless worker.error.nil? }
    self
  end

  # The worker encapsulates the forking of the child process and communication
  # between the parent and the child. Each worker instance is extended with
  # the block or module supplied to the pre-forking pool that created the
  # worker.
  #
  class Worker

    attr_reader :prefork
    attr_reader :error

    # Create a new worker that belongs to the _prefork_ pool.
    #
    def initialize( prefork )
      @prefork = prefork
      @thread = nil
      @piper = nil
      @error = nil
    end

    # Start this worker. A new process will be forked, and the code supplied
    # by the user to the prefork pool will be executed in the child process.
    #
    def start
      return unless @thread.nil?

      @error = nil
      @piper = ::Servolux::Piper.new('rw', :timeout => @prefork.timeout)
      parent if @piper.parent?
      child if @piper.child?
      self
    end

    # Stop this worker. The internal worker thread is stopped and a 'HUP'
    # signal is sent to the child process. This method will return immediately
    # without waiting for the child process to exit. Use the +wait+ method
    # after calling +stop+ if your code needs to know when the child exits.
    #
    def stop
      return if @thread.nil? or @piper.nil? or @piper.child?

      @thread[:stop] = true
      @thread.wakeup
      Thread.pass until !@thread.status
      kill 'HUP'
      @thread = nil
      self
    end

    # Wait for the child process to exit. This method returns immediately when
    # called from the child process or if the child process has not yet been
    # forked.
    #
    def wait
      return if @piper.nil? or @piper.child?
      Process.wait(@piper.pid, Process::WNOHANG|Process::WUNTRACED)
    end

    # Send this given _signal_ to the child process. The default signal is
    # 'TERM'. This method will return immediately.
    #
    def kill( signal = 'TERM' )
      return if @piper.nil?
      @piper.signal signal
    rescue Errno::ESRCH, Errno::ENOENT
      return nil
    end

    # Returns +true+ if the child process is alive. Returns +nil+ if the child
    # process has not been started.
    #
    # Always returns +nil+ when called from the child process.
    #
    def alive?
      return if @piper.nil?
      @piper.alive?
    end


    private

    # This code should only be executed in the parent process.
    #
    def parent
      @thread = Thread.new {
        response = nil
        begin
          @piper.puts START
          Thread.current[:stop] = false
          loop {
            break if Thread.current[:stop]
            @piper.puts HEARTBEAT
            response = @piper.gets(ERROR)
            break if Thread.current[:stop]

            case response
            when HEARTBEAT; next
            when START; break
            when ERROR
              raise Timeout,
                    "Child did not respond in a timely fashion. Timeout is set to #{@prefork.timeout} seconds."
            when Exception
              raise response
            else
              raise UnknownResponse,
                    "Child returned unknown response: #{response.inspect}"
            end
          }
        rescue Exception => err
          @error = err
        ensure
          @piper.timeout = 0
          @piper.puts HALT rescue nil
          @piper.close
          self.start if START == response
        end
      }
      Thread.pass until @thread[:stop] == false
    end

    # This code should only be executed in the child process. It wraps the
    # user supplied "execute" code in a loop, and takes care of handling
    # signals and communication with the parent.
    #
    def child
      @thread = Thread.current

      # if we get a HUP signal, then tell the parent process to stop this
      # child process and start a new one to replace it
      Signal.trap('HUP') {
        @piper.puts START rescue nil
        @thread.wakeup
      }

      before_executing if self.respond_to? :before_executing
      :wait until @piper.gets == START

      loop {
        signal = @piper.gets(ERROR)
        case signal
        when HEARTBEAT
          execute
          @piper.puts HEARTBEAT
        when HALT
          break
        when ERROR
          raise Timeout,
                "Parent did not respond in a timely fashion. Timeout is set to #{@prefork.timeout} seconds."
        else
          raise UnknownSignal,
                "Child received unknown signal: #{signal.inspect}"
        end
      }
      after_executing if self.respond_to? :after_executing
    rescue Exception => err
      @piper.puts err rescue nil
    ensure
      @piper.close
      exit!
    end
  end  # class Worker

end  # class Servolux::Prefork

