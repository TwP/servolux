
class Servolux::Prefork
  include ::Servolux::Threaded

  Timeout = Class.new(::Servolux::Error)
  UnexpectedResponse = Class.new(::Servolux::Error)

  # :stopdoc:
  START = "\000START".freeze
  HALT = "\000HALT".freeze
  ERROR = "\000FUCK".freeze
  HEARTBEAT = "\000<3".freeze
  # :startdoc:

  attr_accessor :timeout

  #
  #    :timeout
  #
  def initialize( opts = {}, &block )
    @timeout = opts[:timeout]
    @module = opts[:module]
    @module = Module.new { define_method :execute, &block } if block
    @workers = []
  end

  def start( number )
    @workers.clear

    number.times {
      @workers << Worker.new(self)
      @workers.last.extend @module
    }
    @workers.each { |worker| worker.start }
  end

  def stop
    @workers.each { |worker| worker.stop rescue nil }
    @workers.each { |worker| worker.wait rescue nil }
  end

  def each_worker( &block )
    @workers.each(&block)
  end

  def errors
    @workers.each { |worker| yield worker unless worker.error.nil? }
  end

  #
  #
  class Worker

    attr_accessor :prefork
    attr_reader :error

    #
    #
    def initialize( prefork )
      @prefork = prefork
      @thread = nil
      @piper = nil
      @error = nil
    end

    #
    #
    def start
      @piper = ::Servolux::Piper.new('rw', :timeout => @prefork.timeout)
      parent if @piper.parent?
      child if @piper.child?
    end

    #
    #
    def stop
      return if @thread.nil? or @piper.nil? or @piper.child?

      @thread[:stop] = true
      @thread.wakeup
    end

    # Wait for the child process to exit. This method returns immediately when
    # called from the child process or if the child process has not yet been
    # forked.
    #
    def wait
      return if @piper.nil? or @piper.child?
      Process.waitpid(@piper.pid, Process::WNOHANG|Process::WUNTRACED)
    end

    #
    #
    def kill( signal = 'TERM' )
      return if @piper.nil?
      @piper.signal signal
    rescue Errno::ESRCH, Errno::ENOENT
      return nil
    end


    private

    #
    #
    def parent
      @thread = Thread.new {
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
            when Exception; raise response
            when ERROR
              raise Timeout,
                    "Child did not respond in a timely fashion. Timeout is set to #{@prefork.timeout} seconds."
            else
              raise UnexpectedResponse,
                    "Child returned unexpected response: #{response.inspect}"
            end
          }
        rescue Exception => err
          @error = err
        ensure
          @piper.timeout = 0
          @piper.puts HALT rescue nil
          @piper.close
        end
      }
      Thread.pass until @thread[:stop] == false
    end

    #
    #
    def child
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
          raise UnexpectedSignal,
                "Child received unexpected signal: #{signal.inspect}"
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

