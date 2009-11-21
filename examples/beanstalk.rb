# Preforking Beanstalkd job runner using Servolux.
#
# In this example, we prefork 7 processes each of which connect to our
# Beanstalkd queue and then wait for jobs to process. We are using a module so
# that we can connect to the beanstalk queue before exectuing and then
# disconnect from the beanstalk queue after exiting. These methods are called
# exactly once per child process.
#
# A variation on this is to load source code in the before_executing method
# and initialize an object that will process jobs. This is advantagous because
# now you can send SIGHUP to a child process and it will restart, loading your
# Ruby libraries before executing. Now you can do a rolling deploy of new
# code.
#
#   def before_executing
#     Kernel.load '/your/source/code.rb'
#     @job_runner = Your::Source::Code::JobRunner.new
#   end
# --------

require 'servolux'
require 'beanstalk-client'

module JobProcessor
  # Open a connection to our beanstalk queue
  def before_executing
    @beanstalk = Beanstalk::Pool.new(['localhost:11300'])
  end

  # Close the connection to our beanstalk queue
  def after_executing
    @beanstalk.close
  end

  # Reserve a job from the beanstalk queue, and processes jobs as we receive
  # them. We have a timeout set for 2 minutes so that we can send a heartbeat
  # back to the parent process even if the beanstalk queue is empty.
  def execute
    job = @beanstalk.reserve(120) rescue nil
    if job
      # process job here ...
      job.delete
    end
  end
end

# Create our preforking worker pool. Each worker will run the code found in
# the JobProcessor module. We set a timeout of 10 minutes. The child process
# must send a "heartbeat" message to the parent within this timeout period;
# otherwise, the parent will halt the child process.
#
# Our execute code in the JobProcessor takes this into account. It will wakeup
# every 2 minutes, if no jobs are reserved from the beanstalk queue, and send
# the heartbeat message.
#
# This also means that if any job processed by a worker takes longer than 10
# minutes to run, that child worker will be killed.
pool = Servolux::Prefork.new(:timeout => 600, :module => JobProcessor)

# Start up 7 child processes to handle jobs
pool.start 7

# Stop when SIGINT is received.
trap('INT') { pool.stop }
Process.waitall
