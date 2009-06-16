
require 'logging'

module Servolux

  # :stopdoc:
  VERSION = '1.0.0'
  LIBPATH = ::File.expand_path(::File.dirname(__FILE__)) + ::File::SEPARATOR
  PATH = ::File.dirname(LIBPATH) + ::File::SEPARATOR
  # :startdoc:
  
  # Generic Servolux Error class.
  Error = Class.new(StandardError)

  # Returns the version string for the library.
  #
  def self.version
    VERSION
  end

  # Returns the library path for the module. If any arguments are given,
  # they will be joined to the end of the libray path using
  # <tt>File.join</tt>.
  #
  def self.libpath( *args )
    args.empty? ? LIBPATH : ::File.join(LIBPATH, args.flatten)
  end

  # Returns the lpath for the module. If any arguments are given,
  # they will be joined to the end of the path using
  # <tt>File.join</tt>.
  #
  def self.path( *args )
    args.empty? ? PATH : ::File.join(PATH, args.flatten)
  end

  # Returns +true+ if the execution platform supports fork.
  #
  def self.fork?
    RUBY_PLATFORM != 'java' and test(?e, '/dev/null')
  end

end  # module Servolux

%w[threaded server daemon].each do |lib|
  require Servolux.libpath('servolux', lib)
end

# EOF
