
unless defined? SERVOLUX_SPEC_HELPER
SERVOLUX_SPEC_HELPER = true

require 'rubygems'
require 'spec'
require 'spec/logging_helper'

require File.expand_path(
    File.join(File.dirname(__FILE__), %w[.. lib servolux]))

include Logging.globally

Spec::Runner.configure do |config|
  include Spec::LoggingHelper
  config.capture_log_messages

  # == Mock Framework
  #
  # RSpec uses it's own mocking framework by default. If you prefer to
  # use mocha, flexmock or RR, uncomment the appropriate line:
  #
  # config.mock_with :mocha
  # config.mock_with :flexmock
  # config.mock_with :rr
end

end  # unless defined?
# EOF
