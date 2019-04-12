# vpn cookbook
Install and configure [OpenVPN](https://openvpn.net/).

## Usage

### OpenVPN server

Install OpenVPN server packages, configure a Certification Authority and launch the service.

```ruby
vpn_server 'lan' do
  fqdn 'vpn.acme.corp'
  user 'vagrant'
  group 'vagrant'
  certificate(
    country: 'RU',
    province: 'Samara',
    city: 'Samara',
    org: 'ACME Corp.',
    email: 'admin@acme.corp',
    ou: 'IT'
  )
  port 1194
  network '10.1.0.0/24'
  openvpn(
    proto: 'tcp',
    cipher: 'AES-128-CBC'
  )
action :setup
end
```

In this particular case, the service name is `openvpn@lan`.

### OpenVPN client

Configure an OpenVPN client with a static IPv4 address.

```ruby
vpn_client 'Alice VPN connection' do
  name 'alice'
  user 'vagrant'
  group 'vagrant'
  server 'lan'
  ipv4_address '10.1.0.3'
  action :create
end
```

In this particular case `*.ovpn` configuration files are stored in `/etc/chef-vpn/client-config/lan/files` directory.

## License
MIT © [Alexander Pyatkin](https://github.com/aspyatkin)
