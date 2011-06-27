# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{larch}
  s.version = "1.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = [%q{Ryan Grove}]
  s.date = %q{2011-06-27}
  s.email = %q{ryan@wonko.com}
  s.executables = [%q{larch}]
  s.files = [%q{HISTORY}, %q{LICENSE}, %q{README.rdoc}, %q{bin/larch}, %q{lib/larch/config.rb}, %q{lib/larch/db/account.rb}, %q{lib/larch/db/mailbox.rb}, %q{lib/larch/db/message.rb}, %q{lib/larch/db/migrate/001_create_schema.rb}, %q{lib/larch/db/migrate/002_add_timestamps.rb}, %q{lib/larch/errors.rb}, %q{lib/larch/imap/mailbox.rb}, %q{lib/larch/imap.rb}, %q{lib/larch/logger.rb}, %q{lib/larch/monkeypatch/net/imap.rb}, %q{lib/larch/version.rb}, %q{lib/larch.rb}]
  s.homepage = %q{https://github.com/rgrove/larch/}
  s.require_paths = [%q{lib}]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.6")
  s.rubygems_version = %q{1.8.5}
  s.summary = %q{Larch copies messages from one IMAP server to another. Awesomely.}

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<amalgalite>, ["~> 1.0"])
      s.add_runtime_dependency(%q<highline>, ["~> 1.5"])
      s.add_runtime_dependency(%q<sequel>, ["~> 3.14"])
      s.add_runtime_dependency(%q<trollop>, ["~> 1.13"])
    else
      s.add_dependency(%q<amalgalite>, ["~> 1.0"])
      s.add_dependency(%q<highline>, ["~> 1.5"])
      s.add_dependency(%q<sequel>, ["~> 3.14"])
      s.add_dependency(%q<trollop>, ["~> 1.13"])
    end
  else
    s.add_dependency(%q<amalgalite>, ["~> 1.0"])
    s.add_dependency(%q<highline>, ["~> 1.5"])
    s.add_dependency(%q<sequel>, ["~> 3.14"])
    s.add_dependency(%q<trollop>, ["~> 1.13"])
  end
end
