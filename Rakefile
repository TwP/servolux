
begin
  require 'bones'
rescue LoadError
  abort '### please install the "bones" gem ###'
end

task :default => 'spec:run'
task 'gem:release' => 'spec:run'

Bones {
  name         'servolux'
  summary      'A collection of tools for working with processes'
  authors      'Tim Pease'
  email        'tim.pease@gmail.com'
  url          'http://rubygems.org/gems/servolux'
  readme_file  'README.md'
  spec.opts << '--color' << '--format documentation'

  use_gmail

  depend_on  'bones-rspec', '~> 2.0',  :development => true
  depend_on  'bones-git',   '~> 1.3',  :development => true
  depend_on  'logging',     '~> 2.0',  :development => true
}
