
require 'thread'

class Servolux::Prefork::JobQueue < ::Servolux::Prefork

  attr_reader :job_queue

  #
  #
  def initialize( opts = {}, &block )
    opts[:module] = Module.new { define_method :process, &block } if block
    super(opts)

    @job_queue = Queue.new
  end

  #
  #
  def run( job, &callback )
    @job_queue.push([job, callback])
  end

  # Start up the given _number_ of job workers. Each worker will create a
  # child process and run the user supplied job processing code in that child
  # process.
  #
  # @param [Integer] number The number of workers to prefork
  # @return [Prefork] self
  #
  def start( number )
    @workers.clear

    number.times {
      @workers << JobWorker.new(self)
      @workers.last.extend @module
    }
    @workers.each { |worker| worker.start }
    self
  end


  class JobWorker < ::Servolux::Prefork::Worker

    private

    # This code should only be executed in the parent process.
    #
    def parent
      @thread = Thread.new {
        restart = false
        begin
          @piper.puts START
          Thread.current[:stop] = false
          loop {
            unless restart
              break if Thread.current[:stop]
              job, callback = @prefork.job_queue.pop
              break if job.nil?
              @piper.puts job
            end

            result = @piper.gets(ERROR)

            case result
            when START
              restart = true
              next
            when ERROR
              raise Timeout,
                    "Child did not respond in a timely fashion. Timeout is set to #{@prefork.timeout.inspect} seconds."
            when Exception
              @error = result
              break
            else
              callback.call(result)
              callback = nil
              break if restart
            end
          }
        ensure
          self._close
          self.start if restart and !Thread.current[:stop] and @error.nil?
        end
      }
      Thread.pass until @thread[:stop] == false
    end

    # This code should only be executed in the child process. It wraps the
    # user supplied "process" code in a loop, and takes care of handling
    # signals and communication with the parent.
    #
    def child
      @thread = Thread.current

      # if we get a HUP signal, then tell the parent process to stop this
      # child process and start a new one to replace it
      Signal.trap('HUP') {
        @piper.puts START rescue nil
        Thread.new { self.hup } if self.respond_to? :hup
      }

      Signal.trap('TERM') {
        self._close
        Thread.new { self.term } if self.respond_to? :term
      }

      before_processing if self.respond_to? :before_processing
      :wait until @piper.gets == START

      loop {
        job = @piper.gets(HEARTBEAT)
        case job
        when HEARTBEAT; next
        when HALT; break
        else
          result = process job
          @piper.puts result
        end
      }
    rescue Exception => err
      @piper.puts err rescue nil
    ensure
      after_executing rescue nil if self.respond_to? :after_executing
      self._close
      exit!
    end
  end

end
