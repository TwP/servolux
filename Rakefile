
begin
  require 'bones'
rescue LoadError
  abort '### please install the "bones" gem ###'
end

ensure_in_path 'lib'
require 'servolux'

task :default => 'spec:specdoc'
task 'gem:release' => ['spec:run', 'rubyforge:release']

Bones {
  name         'servolux'
  authors      'Tim Pease'
  email        'tim.pease@gmail.com'
  url          'http://gemcutter.org/gems/servolux'
  version      Servolux::VERSION
  readme_file  'README.rdoc'
  ignore_file  '.gitignore'

  spec.opts << '--color'
  rubyforge.name 'codeforpeople'

  use_gmail

  depend_on  'bones-extras', :development => true
  depend_on  'bones-git',    :development => true
  depend_on  'logging',      :development => true
  depend_on  'rspec',        :development => true
}
