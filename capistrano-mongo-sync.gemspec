Gem::Specification.new do |gem|
  gem.name        = 'capistrano-mongo-sync'
  gem.version     = '0.1.6'
  gem.date        = '2018-01-18'
  gem.summary     = "A tool for keeping local mongo in sync with remote"
  gem.description = "A tool for keeping local mongo in sync with remote"
  gem.authors     = ["Open Listings Engineering", "We're hiring!"]
  gem.email       = 'engineering@openlistings.com'
  gem.homepage    = 'https://github.com/openlistings/capistrano-mongo-sync'
  gem.license     = 'MIT'

  gem.files         = `git ls-files`.split($/)
  gem.test_files    = gem.files.grep(%r{^(test)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'capistrano', '~> 3.1'
  gem.add_dependency 'sshkit', '~> 1.2'

  gem.add_development_dependency 'minitest', '~> 5.8'
  gem.add_development_dependency 'mocha', '~> 1.1'

end
