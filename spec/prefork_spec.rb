require File.expand_path('../spec_helper', __FILE__)
require 'tempfile'
require 'fileutils'
require 'enumerator'

if Servolux.fork?
describe Servolux::Prefork do
  def pids
    workers.map! { |w| w.pid }
  end

  def workers
    ary = []
    return ary if @prefork.nil?
    @prefork.each_worker { |w| ary << w }
    ary
  end

  def worker_count
    Dir.glob(@glob).length
  end

  def alive?( pid )
    _, cstatus = Process.wait2( pid, Process::WNOHANG )
    return false if cstatus
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::ENOENT, Errno::ECHILD
    false
  end

  before :all do
    tmp = Tempfile.new 'servolux-prefork'
    @path = tmp.path; tmp.unlink
    @glob = @path + '/*.txt'
    FileUtils.mkdir @path

    @worker = Module.new do
      def before_executing() @fd = File.open("#{config[:path]}/#$$.txt", 'w'); end
      def after_executing() @fd.close; FileUtils.rm_f @fd.path; end
      def execute() @fd.puts Time.now; sleep 2; end
      def hup() @thread.wakeup; end
      alias :term :hup
    end
  end

  after :all do
    FileUtils.rm_rf @path
  end

  before :each do
    @prefork = nil
    FileUtils.rm_f "#@path/*.txt"
  end

  after :each do
    next if @prefork.nil?
    @prefork.stop
    @prefork.each_worker { |worker| worker.signal('KILL') }
    @prefork = nil
    FileUtils.rm_f "#@path/*.txt"
  end

  it "starts up a single worker" do
    @prefork = Servolux::Prefork.new :module => @worker, :config => {:path => @path}
    @prefork.start 1
    ary = workers
    sleep 0.1 until ary.all? { |w| w.alive? }
    sleep 0.1 until worker_count >= 1

    ary = Dir.glob(@glob)
    expect(ary.length).to eq(1)
    expect(File.basename(ary.first).to_i).to eq(pids.first)
  end

  it "starts up a number of workers" do
    @prefork = Servolux::Prefork.new :module => @worker, :config => {:path => @path}
    @prefork.start 8
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 8

    ary = Dir.glob(@glob)
    expect(ary.length).to eq(8)

    ary.map! { |fn| File.basename(fn).to_i }.sort!
    expect(ary).to eq(pids.sort)
  end

  it "stops workers gracefullly" do
    @prefork = Servolux::Prefork.new :module => @worker, :config => {:path => @path}
    @prefork.start 3
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 3

    ary = Dir.glob(@glob)
    expect(ary.length).to eq(3)

    @prefork.stop
    sleep 0.250 until Dir.glob(@glob).length == 0
    workers.each { |w| w.wait rescue nil }

    rv = workers.all? { |w| !w.alive? }
    expect(rv).to be true
  end

  it "restarts a worker via SIGHUP" do
    @prefork = Servolux::Prefork.new :module => @worker, :config => {:path => @path}
    @prefork.start 2
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 2

    pid = pids.last
    ary.last.signal 'HUP'
    @prefork.reap until !alive? pid
    sleep 0.250 until ary.all? { |w| w.alive? }

    expect(pid).not_to eq(pids.last)
  end

  it "starts up a stopped worker" do
    @prefork = Servolux::Prefork.new :module => @worker, :config => {:path => @path}
    @prefork.start 2
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 2

    pid = pids.last
    ary.last.signal 'TERM'

    @prefork.reap until !alive? pid
    @prefork.each_worker do |worker|
      worker.start unless worker.alive?
    end
    sleep 0.250 until ary.all? { |w| w.alive? }
    expect(pid).not_to eq(pids.last)
  end

  it "adds a new worker to the worker pool" do
    @prefork = Servolux::Prefork.new :module => @worker, :config => {:path => @path}
    @prefork.start 2
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 2


    @prefork.add_workers( 2 )
    sleep 0.250 until worker_count >= 4
    expect(workers.size).to eq(4)
  end

  it "only adds workers up to the max_workers value" do
    @prefork = Servolux::Prefork.new :module => @worker, :max_workers => 3, :config => {:path => @path}
    @prefork.start 2
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 2

    @prefork.add_workers( 2 )
    sleep 0.250 until worker_count >= 3
    expect(workers.size).to eq(3)
  end

  it "prunes workers that are no longer running" do
    @prefork = Servolux::Prefork.new :module => @worker, :config => {:path => @path}
    @prefork.start 2
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 2

    @prefork.add_workers( 2 )
    sleep 0.250 until worker_count >= 3
    expect(workers.size).to eq(4)

    workers[0].stop
    sleep 0.250 while workers[0].alive?

    @prefork.prune_workers
    expect(workers.size).to eq(3)
  end

  it "ensures that there are minimum number of workers" do
    @prefork = Servolux::Prefork.new :module => @worker, :min_workers => 3, :config => {:path => @path}
    @prefork.start 1
    ary = workers
    sleep 0.250 until ary.all? { |w| w.alive? }
    sleep 0.250 until worker_count >= 1

    @prefork.ensure_worker_pool_size
    sleep 0.250 until worker_count >= 3
    expect(workers.size).to eq(3)
  end
end
end  # Servolux.fork?
