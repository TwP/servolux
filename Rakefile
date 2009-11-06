
begin
  require 'bones'
rescue LoadError
  abort '### please install the "bones" gem ###'
end

ensure_in_path 'lib'
require 'servolux'

task :default => 'spec:specdoc'

Bones {
  name         'servolux'
  authors      'Tim Pease'
  email        'tim.pease@gmail.com'
  url          'http://gemcutter.org/gems/servolux'
  version      Servolux::VERSION
  readme_file  'README.rdoc'
  ignore_file  '.gitignore'

  spec.opts << '--color'

  use_gmail

  depend_on  'logging'
  depend_on  'rspec',        :development => true
  depend_on  'bones-extras', :development => true
}
