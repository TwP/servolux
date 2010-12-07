
begin
  require 'bones'
rescue LoadError
  abort '### please install the "bones" gem ###'
end

task :default => 'spec:run'
task 'gem:release' => 'spec:run'

Bones {
  name         'servolux'
  authors      'Tim Pease'
  email        'tim.pease@gmail.com'
  url          'http://gemcutter.org/gems/servolux'
  readme_file  'README.rdoc'
  ignore_file  '.gitignore'
  spec.opts << '--color'

  use_gmail

  depend_on  'bones-rspec',  :development => true
  depend_on  'bones-git',    :development => true
  depend_on  'logging',      :development => true
}
