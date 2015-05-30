class Servolux::PidFile

  DEFAULT_MODE = 0640

  attr_accessor :name
  attr_accessor :mode

  #
  # opts - The options Hash
  #   :name - the name of the PID file
  #
  def initialize( opts = {} )
    @name = opts.fetch(:name, nil)
    @pid  = opts.fetch(:pid, nil)
    @mode = opts.fetch(:mode, DEFAULT_MODE)

    yield self if block_given?
  end

  #
  #
  def write( pid: Process.pid )
    @pid ||= pid
    File.open(name, 'w', mode) { |fd| fd.write(@pid.to_s) }
  end

  #
  #
  def pid
    return @pid unless @pid.nil?
    @pid =
      if name && File.exists?(name)
        Integer(File.read(pid_file).strip)
      end
  end

end
