class Servolux::PidFile

  DEFAULT_MODE = 0640

  attr_accessor :name
  attr_accessor :mode
  attr_accessor :path

  #
  # opts - The options Hash
  #   :name - the name of the program
  #   :path - path to the PID file location
  #   :mode - file permissions mode
  #   :pid  - the numeric process ID
  #
  def initialize( opts = {} )
    @name = opts.fetch(:name, $0)
    @path = opts.fetch(:path, nil)
    @mode = opts.fetch(:mode, DEFAULT_MODE)
    @pid  = opts.fetch(:pid, nil)

    yield self if block_given?
  end

  #
  #
  def filename
    fn = "#{name}.pid"
    fn = File.join(path, fn) unless path.nil?
    fn
  end

  #
  #
  def write( pid = Process.pid )
    @pid ||= pid
    File.open(filename, 'w', mode) { |fd| fd.write(@pid.to_s) }
  end

  #
  #
  def delete
    return unless exist?
    return unless read_pid == Process.pid
    File.delete filename
  end

  #
  #
  def delete!
    return unless exist?
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
  def read_pid
    Integer(File.read(filename).strip) if exist?
  end
end
