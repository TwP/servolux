require File.expand_path('../spec_helper', __FILE__)

describe Servolux::PidFile do
  before :all do
    tmp = Tempfile.new "servolux-pid-file"
    @path = tmp.path; tmp.unlink
    FileUtils.mkdir @path
  end

  after :all do
    FileUtils.rm_rf @path
  end

  before :each do
    FileUtils.rm_f Dir.glob("#@path/*.pid")
    @pid_file = Servolux::PidFile.new(:name => "test", :path => @path)
    @filename = @pid_file.filename
  end

  describe "creating" do
    it "writes a PID file" do
      expect(test(?e, @filename)).to be false

      @pid_file.write(123456)
      expect(test(?e, @filename)).to be true

      pid = Integer(File.read(@filename).strip)
      expect(pid).to eq(123456)
    end

    it "uses mode rw-r----- by default" do
      expect(test(?e, @filename)).to be false

      @pid_file.write
      expect(test(?e, @filename)).to be true

      mode = File.stat(@filename).mode & 0777
      expect(mode).to eq(0640)
    end

    it "uses the given mode" do
      @pid_file.mode = 0400
      expect(test(?e, @filename)).to be false

      @pid_file.write
      expect(test(?e, @filename)).to be true

      mode = File.stat(@filename).mode & 0777
      expect(mode).to eq(0400)
    end
  end

  describe "deleting" do
    it "removes a PID file" do
      expect(test(?e, @filename)).to be false
      expect { @pid_file.delete }.not_to raise_error

      @pid_file.write
      expect(test(?e, @filename)).to be true

      @pid_file.delete
      expect(test(?e, @filename)).to be false
    end

    it "removes the PID file only from the same process" do
      @pid_file.write(654321)
      expect(test(?e, @filename)).to be true

      @pid_file.delete
      expect(test(?e, @filename)).to be true
    end

    it "can forcibly remove a PID file" do
      @pid_file.write(135790)
      expect(test(?e, @filename)).to be true

      @pid_file.delete!
      expect(test(?e, @filename)).to be false
    end
  end

  it "returns the PID from the file" do
    expect(@pid_file.pid).to be_nil

    File.open(@filename, 'w') { |fd| fd.write(314159) }
    expect(@pid_file.pid).to eq(314159)

    File.delete(@filename)
    expect(@pid_file.pid).to be_nil
  end

  it "sends a signal to the process"

  it "reports if the process is alive"
end
