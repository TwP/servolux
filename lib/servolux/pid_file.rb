class Servolux::PidFile

  DEFAULT_MODE = 0640

  attr_accessor :name     # the process name
  attr_accessor :path     # the path to the PID file
  attr_accessor :mode     # PID file permissions mode
  attr_accessor :logger   # logger for outputting messages

  #
  # opts - The options Hash
  #   :name   - the name of the program
  #   :path   - path to the PID file location
  #   :mode   - file permissions mode
  #   :pid    - the numeric process ID
  #   :logger - logger for outputting messages
  #
  def initialize( opts = {} )
    @name   = opts.fetch(:name, $0)
    @path   = opts.fetch(:path, ".")
    @mode   = opts.fetch(:mode, DEFAULT_MODE)
    @pid    = opts.fetch(:pid, nil)
    @logger = opts.fetch(:logger, Servolux::NullLogger())

    yield self if block_given?
  end

  #
  #
  def filename
    fn = name.to_s.downcase.tr(" ","_") + ".pid"
    fn = File.join(path, fn) unless path.nil?
    fn
  end

  #
  #
  def write( pid = Process.pid )
    @pid ||= pid
    fn = filename
    logger.debug "Writing pid file #{fn.inspect}"
    File.open(filename, 'w', mode) { |fd| fd.write(@pid.to_s) }
  end

  #
  #
  def delete
    return unless read_pid == Process.pid
    fn = filename
    logger.debug "Deleting pid file #{fn.inspect}"
    File.delete filename
  end

  #
  #
  def delete!
    return unless exist?
    fn = filename
    logger.debug "Deleting pid file #{fn.inspect}"
    File.delete filename
  end

  #
  #
  def exist?
    File.exist? filename
  end

  # Returns the numeric PID read from the file or `nil` if the file does not
  # exist.
  def pid
    return @pid unless @pid.nil?
    read_pid
  end

  #
  #
  def alive?
    pid = self.pid
    return if pid.nil?

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  #
  #
  def kill( signal = 'INT' )
    pid = self.pid
    return if pid.nil?

    signal = Signal.list.invert[signal] if signal.is_a?(Integer)
    logger.info "Killing PID #{pid} with #{signal}"
    Process.kill(signal, pid)

  rescue Errno::EINVAL
    logger.error "Failed to kill PID #{pid} with #{signal}: " \
                 "'#{signal}' is an invalid or unsupported signal number."
    nil
  rescue Errno::EPERM
    logger.error "Failed to kill PID #{pid} with #{signal}: " \
                 "Insufficient permissions."
    nil
  rescue Errno::ESRCH
    logger.error "Failed to kill PID #{pid} with #{signal}: " \
                 "Process is deceased or zombie."
    nil
  rescue Errno::EACCES => err
    logger.error err.message
    nil
  rescue Errno::ENOENT => err
    logger.error "Could not find a PID file at #{pid_file.inspect}. " \
                 "Most likely the process is no longer running."
    nil
  rescue Exception => err
    unless err.is_a?(SystemExit)
      logger.error "Failed to kill PID #{pid} with #{signal}: #{err.message}"
    end
    nil
  end

  # Internal:
  #
  def read_pid
    Integer(File.read(filename).strip) if exist?
  rescue Errno::EACCES => err
    logger.error "You do not have access to the PID file at " \
                 "#{filename.inspect}: #{err.message}"
    nil
  end
end
