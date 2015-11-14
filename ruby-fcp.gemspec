Gem::Specification.new do |s|
  s.name        = 'ruby-fcp'
  s.version     = '0.1.0'
  s.date        = '2015-11-14'
  s.summary     = "FCPClient"
  s.description = "A gem interface for Freenet Client Protocol"
  s.authors     = ["hikiko (author)", "Desyncr (maintainer)"]
  s.email       = 'kerben@i2pmail.org'
  s.files       = Dir['lib/**/*.rb', 'bin/fput', 'bin/fget']
  s.bindir      = 'bin'
  s.executables << 'fget'
  s.executables << 'fput'
  s.homepage    = 'https://github.com/desyncr/ruby-fcp'
  s.license     = 'Unlicense'
end
