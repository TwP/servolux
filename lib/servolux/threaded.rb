
# == Synopsis
# The Threaded module is used to peform some activity at a specified
# interval.
#
# == Details
# Sometimes it is useful for an object to have its own thread of execution
# to perform a task at a recurring interval. The Threaded module
# encapsulates this functionality so you don't have to write it yourself. It
# can be used with any object that responds to the +run+ method.
#
# The threaded object is run by calling the +start+ method. This will create
# a new thread that will invoke the +run+ method at the desired interval.
# Just before the thread is created the +before_starting+ method will be
# called (if it is defined by the threaded object). Likewise, after the
# thread is created the +after_starting+ method will be called (if it is
# defeined by the threaded object).
#
# The threaded object is stopped by calling the +stop+ method. This sets an
# internal flag and then wakes up the thread. The thread gracefully exits
# after checking the flag. Like the start method, before and after methods
# are defined for stopping as well. Just before the thread is stopped the
# +before_stopping+ method will be called (if it is defined by the threaded
# object). Likewise, after the thread has died the +after_stopping+ method
# will be called (if it is defeined by the threaded object).
#
# Calling the +join+ method on a threaded object will cause the calling
# thread to wait until the threaded object has stopped. An optional timeout
# parameter can be given.
#
# == Examples
# Take a look at the Servolux::Server class for an example of a threaded
# object.
#
module Servolux::Threaded

  # This method will be called by the activity thread at the desired
  # interval. Implementing classes are exptect to provide this
  # functionality.
  #
  def run
    raise NotImplementedError,
         'The run method must be defined by the threaded object.'
  end

  # Start the activity thread. If already started this method will return
  # without taking any action.
  #
  # If the including class defines a 'before_starting' method, it will be
  # called before the thread is created and run. Likewise, if the
  # including class defines an 'after_starting' method, it will be called
  # after the thread is created.
  #
  def start
    return self if running?
    logger.debug "Starting"

    before_starting if self.respond_to?(:before_starting)
    @activity_thread_running = true
    @activity_thread_iterations = 0
    @activity_thread = Thread.new {
      begin
        loop {
          sleep interval if running?
          break unless running?
          run
          @activity_thread_iterations += 1
          break if finished_iterations?
        }
        @activity_thread_running = false
      rescue Exception => err
        @activity_thread_running = false
        logger.fatal err unless err.is_a?(SystemExit)
        raise err
      end
    }
    after_starting if self.respond_to?(:after_starting)
    self
  end

  # Stop the activity thread. If already stopped this method will return
  # without taking any action. Otherwise, this method does not return until
  # the activity thread has died or until _limit_ seconds have passed.
  #
  # If the including class defines a 'before_stopping' method, it will be
  # called before the thread is stopped. Likewise, if the including class
  # defines an 'after_stopping' method, it will be called after the thread
  # has stopped.
  #
  def stop( limit = nil )
    return self unless running?
    logger.debug "Stopping"

    @activity_thread_running = false
    before_stopping if self.respond_to?(:before_stopping)
    @activity_thread.wakeup
    join limit
    @activity_thread = nil
    after_stopping if self.respond_to?(:after_stopping)
    self
  end

  # Wait on the activity thread.  If the thread is already stopped, this
  # method will return without taking any action.  Otherwise, this method
  # does not return until the activity thread has stopped, or a specific
  # number of iterations has passed since this method was called.
  #
  def wait( limit = nil )
    return self unless running?
    start_waiting_iterations = self.iterations
    loop {
      break unless running?
      break if limit and self.iterations > ( start_waiting_iterations + limit )
    }
  end

  # If the activity thread is running, the calling thread will suspend
  # execution and run the activity thread. This method does not return until
  # the activity thread is stopped or until _limit_ seconds have passed.
  #
  # If the activity thread is not running, this method returns immediately
  # with +nil+.
  #
  def join( limit = nil )
    return if @activity_thread.nil?
    @activity_thread.join(limit) ? self : nil
  end

  # Returns +true+ if the activity thread is running. Returns +false+
  # otherwise.
  #
  def running?
    @activity_thread_running
  end

  # Returns +true+ if the activity thread has finished its maximum
  # number of iterations or the thread is no longer running.
  # Returns +false+ otherwise.
  #
  def finished_iterations?
    if running? then
      if @activity_thread_maximum_iterations and
         (@activity_thread_iterations >= @activity_thread_maximum_iterations) then
        return true
      end
    else
      return true
    end
    return false
  end

  # Returns the status of threaded object.
  #
  #    'sleep'    : sleeping or waiting on I/O
  #    'run'      : executing
  #    'aborting' : aborting
  #    false      : not running or terminated normally
  #    nil        : terminated with an exception
  #
  # If this method returns +nil+, then calling join on the threaded object
  # will cause the exception to be raised in the calling thread.
  #
  def status
    return false if @activity_thread.nil?
    @activity_thread.status
  end

  # Sets the number of seconds to sleep between invocations of the
  # threaded object's 'run' method.
  #
  def interval=( value )
    @activity_thread_interval = value
  end

  # Returns the number of seconds to sleep between invocations of the
  # threaded object's 'run' method.
  #
  def interval
    @activity_thread_interval
  end

  # Sets the maximum number of invocations of the threaded object's
  # 'run' method
  #
  def maximum_iterations=( value )
    raise ArgumentError, "maximum iterations must be >= 1" unless value.to_i >= 1
    @activity_thread_maximum_iterations = value
  end

  # Returns the maximum number of invocations of the threaded
  # object's 'run' method
  #
  def maximum_iterations
    @activity_thread_maximum_iterations || 0
  end

  # Returns the number of iterations so far of the threaded object's
  # 'run' method.
  #
  def iterations
    @activity_thread_iterations || 0
  end

  # :stopdoc:
  #
  # The JRuby platform has an implementation error in it's Thread#join
  # method. In the Matz Ruby Interpreter, Thread#join with a +nil+ argument
  # will sleep forever; in the JRuby implementation, join will return
  # immediately.
  #
  if 'java' == RUBY_PLATFORM
    undef :join
    def join( limit = nil )
      return if @activity_thread.nil?
      if limit.nil?
        @activity_thread.join ? self : nil
      else
        @activity_thread.join(limit) ? self : nil
      end
    end
  end
  # :startdoc:

end  # module Servolux::Threaded

# EOF
