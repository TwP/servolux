# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{servolux}
  s.version = "0.4.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Tim Pease"]
  s.date = %q{2009-06-29}
  s.description = %q{Threads : Servers : Forks : Daemons : Serv-O-Lux has them all!}
  s.email = %q{tim.pease@gmail.com}
  s.extra_rdoc_files = ["History.txt", "README.rdoc"]
  s.files = ["History.txt", "README.rdoc", "Rakefile", "foo.rb", "lib/servolux.rb", "lib/servolux/child.rb", "lib/servolux/daemon.rb", "lib/servolux/piper.rb", "lib/servolux/server.rb", "lib/servolux/threaded.rb", "spec/piper_spec.rb", "spec/server_spec.rb", "spec/servolux_spec.rb", "spec/spec_helper.rb", "spec/threaded_spec.rb"]
  s.has_rdoc = true
  s.homepage = %q{http://codeforpeople.rubyforge.org/servolux}
  s.rdoc_options = ["--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{codeforpeople}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Threads : Servers : Forks : Daemons : Serv-O-Lux has them all!}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<logging>, [">= 1.1.2"])
      s.add_runtime_dependency(%q<rspec>, [">= 1.2.2"])
      s.add_development_dependency(%q<bones>, [">= 2.5.0"])
    else
      s.add_dependency(%q<logging>, [">= 1.1.2"])
      s.add_dependency(%q<rspec>, [">= 1.2.2"])
      s.add_dependency(%q<bones>, [">= 2.5.0"])
    end
  else
    s.add_dependency(%q<logging>, [">= 1.1.2"])
    s.add_dependency(%q<rspec>, [">= 1.2.2"])
    s.add_dependency(%q<bones>, [">= 2.5.0"])
  end
end
