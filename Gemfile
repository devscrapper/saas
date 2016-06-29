#referentiels
source "http://rubygems.org"
source "http://gems.github.com"
# utiliser en dev net-ssh 2.6.x et pas > sinon capistrano n'arrive plus � se connecter � la machine distante. Si n�cessire en prod alors utiliser les groupes

gem 'eventmachine', '~> 1.0.8'
gem 'em-http-server', '~> 0.1.8'
gem 'logging', '~> 2.0.0'
gem 'rufus-scheduler', '~> 2.0.24'
gem 'ruby-progressbar', '~> 1.7.5'
gem 'rest-client', '~> 1.8.0'


gem 'selenium-webdriver', '2.50.0'
gem 'hpricot', '0.8.6'
gem 'nokogiri', '1.6.0'
gem 'thread', '0.1.4'
gem 'trollop', '2.0'

gem 'user-agent-randomizer', '~> 0.2.0'
gem 'headless', '2.2.0'
gem 'addressable', '2.3.8'
gem 'domainatrix', '~> 0.0.10'



# fin new gem


group :development do
  gem 'capistrano-rvm'
  gem 'capistrano', '~> 3.1'
  gem 'capistrano-bundler', '~> 1.1.2'
  gem 'sshkit-sudo'
gem 'tzinfo-data', '~> 1.2014.5'

end

group :test do

end

group :production      do
gem 'jwt', '~> 0.1.5'
gem 'i18n', '~> 0.7.0'
#gem 'net-ssh', '~> 2.8.0'
end