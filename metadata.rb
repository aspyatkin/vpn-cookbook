name 'vpn'
maintainer 'Alexander Pyatkin'
maintainer_email 'aspyatkin@gmail.com'
license 'MIT'
description 'Install and configure OpenVPN'
version '0.2.1'

source_url 'https://github.com/aspyatkin/vpn-cookbook.git'

depends 'line', '~> 2.1.1'
depends 'firewall', '~> 2.7.0'

gem 'ruby-ip', '~> 0.9'

supports 'ubuntu'
