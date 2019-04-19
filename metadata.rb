name 'vpn'
maintainer 'Alexander Pyatkin'
maintainer_email 'aspyatkin@gmail.com'
license 'MIT'
description 'Install and configure OpenVPN'
version '0.2.3'

scm_url = 'https://github.com/aspyatkin/vpn-cookbook.git'
source_url scm_url if respond_to?(:source_url)
issues_url "#{scm_url}/issues" if respond_to?(:issues_url)

depends 'line', '>= 2.3.0'
depends 'firewall', '~> 2.7.0'

gem 'ruby-ip', '~> 0.9'

supports 'ubuntu'
