require File.expand_path('../spec_helper', __FILE__)

describe Servolux::PidFile do
  before :all do
    tmp = Tempfile.new "servolux-pid-file"
    @path = tmp.path
    tmp.unlink

    @glob = @path + "/*.pid"
    FileUtils.mkdir @path
  end

  after :all do
    FileUtils.rm_rf @path
  end

  before :each do
    FileUtils.rm_f "#@path/*.pid"
    @pid_file = Servolux::PidFile.new "#{@path}/test.pid"
  end
end
