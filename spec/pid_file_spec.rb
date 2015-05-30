require File.expand_path('../spec_helper', __FILE__)

describe Servolux::PidFile do
  before :all do
    tmp = Tempfile.new "servolux-pid-file"
    @path = tmp.path
    tmp.unlink

    @filename = "#@path/servolux-test.pid"
    FileUtils.mkdir @path
  end

  after :all do
    FileUtils.rm_rf @path
  end

  before :each do
    FileUtils.rm_f Dir.glob("#@path/*.pid")
    @pid_file = Servolux::PidFile.new(:name => @filename)
  end

  it "creates a PID file" do
    expect(test(?e, @filename)).to be false

    @pid_file.write(pid: 123456)
    expect(test(?e, @filename)).to be true

    pid = Integer(File.read(@filename).strip)
    expect(pid).to eq(123456)
  end

  it "generates a PID file with mode rw-r----- by default" do
    expect(test(?e, @filename)).to be false

    @pid_file.write
    expect(test(?e, @filename)).to be true

    mode = File.stat(@filename).mode & 0777
    expect(mode).to eq(0640)
  end

  it "generates PID file with the specified permissions" do
    @pid_file.mode = 0400
    expect(test(?e, @filename)).to be false

    @pid_file.write
    expect(test(?e, @filename)).to be true

    mode = File.stat(@filename).mode & 0777
    expect(mode).to eq(0400)
  end

  it "removes a PID file"

  it "returns the PID from the file"

  it "sends a signal to the process"

  it "reports if the process is alive"
end
