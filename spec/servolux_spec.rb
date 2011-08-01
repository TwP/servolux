
require File.expand_path('../spec_helper', __FILE__)

describe Servolux do

  before :all do
    @root_dir = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  end

  it "finds things releative to 'lib'" do
    Servolux.libpath(%w[servolux threaded]).should == File.join(@root_dir, %w[lib servolux threaded])
  end

  it "finds things releative to 'root'" do
    Servolux.path('Rakefile').should == File.join(@root_dir, 'Rakefile')
  end

end

