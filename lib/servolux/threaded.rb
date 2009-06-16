
# The Threaded module is used to peform some activity at a specified
# interval.
#
module Servolux::Threaded

  # This method will be called by the activity thread at the desired
  # interval. Implementing classes are exptect to provide this
  # functionality.
  #
  def run
    raise NotImplementedError,
         'This method must be defined by the threaded object.'
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
    @activity_thread = Thread.new {
      begin
        loop {
          sleep interval
          break unless running?
          run
        }
      rescue Exception => e
        logger.fatal e
      end
    }
    after_starting if self.respond_to?(:after_starting)
    self
  end

  # Stop the activity thread. If already stopped  this method will return
  # without taking any action.
  #
  # If the including class defines a 'before_stopping' method, it will be
  # called before the thread is stopped. Likewise, if the including class
  # defines an 'after_stopping' method, it will be called after the thread
  # has stopped.
  #
  def stop
    return self unless running?
    logger.debug "Stopping"

    before_stopping if self.respond_to?(:before_stopping)
    @activity_thread_running = false
    @activity_thread.wakeup
    @activity_thread.join
    @activity_thread = nil
    after_stopping if self.respond_to?(:after_stopping)
    self
  end

  # If the activity thread is running, the calling thread will suspend
  # execution and run the activity thread. This method does not return until
  # the activity thread is stopped or until _limit_ seconds have passed.
  #
  # If the activity thread is not running, this method returns immediately
  # with +nil+.
  #
  def join( limit = nil )
    @activity_thread.join limit
    self
  rescue NoMethodError
    return self
  end

  # Returns +true+ if the activity thread is running. Returns +false+
  # otherwise.
  #
  def running?
    @activity_thread_running
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

end  # module Servolux::Threaded

# EOF
