# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{larch}
  s.version = "1.1.0.dev.20091206"

  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1") if s.respond_to? :required_rubygems_version=
  s.authors = ["Ryan Grove"]
  s.date = %q{2009-12-06}
  s.default_executable = %q{larch}
  s.email = %q{ryan@wonko.com}
  s.executables = ["larch"]
  s.files = ["HISTORY", "LICENSE", "README.rdoc", "bin/larch", "lib/larch/config.rb", "lib/larch/db/account.rb", "lib/larch/db/mailbox.rb", "lib/larch/db/message.rb", "lib/larch/db/migrate/001_create_schema.rb", "lib/larch/db/migrate/002_add_timestamps.rb", "lib/larch/errors.rb", "lib/larch/imap/mailbox.rb", "lib/larch/imap.rb", "lib/larch/logger.rb", "lib/larch/version.rb", "lib/larch.rb"]
  s.homepage = %q{http://github.com/rgrove/larch/}
  s.require_paths = ["lib"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.6")
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{Larch syncs messages from one IMAP server to another. Awesomely.}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<highline>, ["~> 1.5.0"])
      s.add_runtime_dependency(%q<sequel>, ["~> 3.6.0"])
      s.add_runtime_dependency(%q<sqlite3-ruby>, ["~> 1.2.5"])
      s.add_runtime_dependency(%q<trollop>, ["~> 1.13"])
    else
      s.add_dependency(%q<highline>, ["~> 1.5.0"])
      s.add_dependency(%q<sequel>, ["~> 3.6.0"])
      s.add_dependency(%q<sqlite3-ruby>, ["~> 1.2.5"])
      s.add_dependency(%q<trollop>, ["~> 1.13"])
    end
  else
    s.add_dependency(%q<highline>, ["~> 1.5.0"])
    s.add_dependency(%q<sequel>, ["~> 3.6.0"])
    s.add_dependency(%q<sqlite3-ruby>, ["~> 1.2.5"])
    s.add_dependency(%q<trollop>, ["~> 1.13"])
  end
end
