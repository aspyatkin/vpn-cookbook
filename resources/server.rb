resource_name :vpn_server
property :name, String, name_property: true

property :basedir, String, default: '/etc/chef-vpn'
property :user, String, required: true
property :group, String, required: true

property :certificate, Hash, default: {}

property :key_size, Integer, default: 2048

property :fqdn, String, required: true
property :port, Integer, default: 1194
property :network, String, required: true
property :openvpn, Hash, default: {}

property :redirect_gateway, [TrueClass, FalseClass], default: false
property :bypass_dhcp, [TrueClass, FalseClass], default: true
property :bypass_dns, [TrueClass, FalseClass], default: true
property :manage_firewall_rules, [TrueClass, FalseClass], default: false
property :firewall_filter_rule_position, Integer, default: 50
property :firewall_nat_rule_position, Integer, default: 150

default_action :setup

action :setup do
  %w[
    openvpn
    easy-rsa
  ].each do |pkg_name|
    package pkg_name do
      action :install
    end
  end

  directory new_resource.basedir do
    owner new_resource.user
    group new_resource.group
    mode 0o755
    recursive true
    action :create
  end

  server_basedir = ::File.join(new_resource.basedir, 'server')

  directory server_basedir do
    owner new_resource.user
    group new_resource.group
    mode 0o755
    action :create
  end

  ca_dir_path = ::File.join(server_basedir, new_resource.name)

  execute "create CA directory at #{ca_dir_path}" do
    command "make-cadir #{ca_dir_path}"
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.directory?(ca_dir_path) }
  end

  key_dir_name = 'keys'
  key_name = 'server'

  crt_details = new_resource.certificate
  defaults = {
    'KEY_COUNTRY' => crt_details.fetch(:country, 'US'),
    'KEY_PROVINCE' => crt_details.fetch(:province, 'California'),
    'KEY_CITY' => crt_details.fetch(:city, 'San Francisco'),
    'KEY_ORG' => crt_details.fetch(:org, 'Acme Inc.'),
    'KEY_EMAIL' => crt_details.fetch(:email, ''),
    'KEY_OU' => crt_details.fetch(:ou, ''),
    'KEY_NAME' => key_name,
    'KEY_DIR' => "$EASY_RSA/#{key_dir_name}",
    'KEY_SIZE' => new_resource.key_size
  }

  vars_file_path = ::File.join(ca_dir_path, 'vars')

  defaults.each do |key, val|
    replace_or_add "adjust #{key} in #{vars_file_path}" do
      path vars_file_path
      pattern ::Regexp.new("^export #{key}=.*$")
      line "export #{key}=#{val.is_a?(::Numeric) ? val.to_s : val.dump}"
      replace_only true
      ignore_missing false
      action :edit
    end
  end

  if node['platform'] == 'ubuntu' && node['platform_version'].to_f >= 18.04
    execute "Fix openssl.cnf at #{ca_dir_path}" do
      cwd ca_dir_path
      command 'cp ./openssl-1.0.0.cnf ./openssl.cnf'
      user new_resource.user
      group new_resource.group
      action :run
      not_if { ::File.exist?(::File.join(ca_dir_path, 'openssl.cnf')) }
    end
  end

  key_dir_path = ::File.join(ca_dir_path, key_dir_name)

  bash "clean CA key directory at #{ca_dir_path}" do
    cwd ca_dir_path
    code <<-EOH
      source ./vars
      ./clean-all
    EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if do
      ::Dir.exist?(key_dir_path) && (
        ::Gem::Version.new(RUBY_VERSION) >= ::Gem::Version.new('2.4.0') ?
          !::Dir.empty?(key_dir_path) : (::Dir.entries(key_dir_path).size != 2)
      )
    end
  end

  ca_crt_file_name = 'ca.crt'
  ca_key_file_name = 'ca.key'

  ca_crt_file_path = ::File.join(key_dir_path, ca_crt_file_name)
  ca_key_file_path = ::File.join(key_dir_path, ca_key_file_name)

  bash "initialize CA at #{ca_dir_path}" do
    cwd ca_dir_path
    code <<-EOH
      source ./vars
      ./build-ca --batch
    EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(ca_crt_file_path) && ::File.exist?(ca_key_file_path) }
  end

  server_crt_file_name = "#{key_name}.crt"
  server_key_file_name = "#{key_name}.key"

  server_crt_file_path = ::File.join(key_dir_path, server_crt_file_name)
  server_key_file_path = ::File.join(key_dir_path, server_key_file_name)

  bash "build key server at #{ca_dir_path}" do
    cwd ca_dir_path
    code <<-EOH
      source ./vars
      ./build-key-server --batch #{key_name}
    EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(server_crt_file_path) && ::File.exist?(server_key_file_path) }
  end

  dh_key_file_name = "dh#{new_resource.key_size}.pem"
  dh_key_file_path = ::File.join(key_dir_path, dh_key_file_name)

  bash "build dh key at #{ca_dir_path}" do
    cwd ca_dir_path
    code <<-EOH
      source ./vars
      ./build-dh
    EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(dh_key_file_path) }
  end

  ta_key_file_name = 'ta.key'
  ta_key_file_path = ::File.join(key_dir_path, ta_key_file_name)

  bash "build ta key at #{ca_dir_path}" do
    cwd ca_dir_path
    code <<-EOH
      openvpn --genkey --secret #{key_dir_name}/#{ta_key_file_name}
    EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(ta_key_file_path) }
  end

  openvpn_basedir = ::File.join('/etc', 'openvpn')

  openvpn_service_basedir = ::File.join(openvpn_basedir, new_resource.name)

  directory openvpn_service_basedir do
    owner 'root'
    group node['root_group']
    mode 0o755
    action :create
  end

  client_dir = ::File.join(openvpn_service_basedir, 'clients')

  directory client_dir do
    owner 'root'
    group node['root_group']
    mode 0o755
    action :create
  end

  [
    ca_crt_file_name,
    ca_key_file_name,
    server_crt_file_name,
    server_key_file_name,
    dh_key_file_name,
    ta_key_file_name
  ].each do |file_name|
    file ::File.join(openvpn_service_basedir, file_name) do
      content(lazy { ::IO.read(::File.join(key_dir_path, file_name)) })
      owner 'root'
      group node['root_group']
      mode 0o600
      sensitive true
      action :create
    end
  end

  service_conf_file_path = ::File.join(openvpn_basedir,
                                       "#{new_resource.name}.conf")

  require 'ip'

  openvpn_conf = new_resource.openvpn
  openvpn_proto = openvpn_conf.fetch(:proto, 'udp')
  openvpn_cipher = openvpn_conf.fetch(:cipher, 'AES-256-CBC')
  openvpn_auth = openvpn_conf.fetch(:auth, 'SHA256')

  log_dir = ::File.join('/var', 'log', 'openvpn')

  directory log_dir do
    owner 'root'
    group node['root_group']
    mode 0o755
    action :create
  end

  template service_conf_file_path do
    cookbook 'vpn'
    source 'server.conf.erb'
    owner 'root'
    group node['root_group']
    variables(
      port: new_resource.port,
      proto: openvpn_proto,
      ta_key: ::File.join(new_resource.name, ta_key_file_name),
      cipher: openvpn_cipher,
      auth: openvpn_auth,
      ca: ::File.join(new_resource.name, ca_crt_file_name),
      cert: ::File.join(new_resource.name, server_crt_file_name),
      key: ::File.join(new_resource.name, server_key_file_name),
      dh: ::File.join(new_resource.name, dh_key_file_name),
      network: ::IP.new(new_resource.network),
      ipp_file: ::File.join(new_resource.name, 'ipp.txt'),
      client_dir: ::File.join(new_resource.name, 'clients'),
      status_file: ::File.join(log_dir, "#{new_resource.name}-status.log"),
      redirect_gateway: new_resource.redirect_gateway,
      bypass_dhcp: new_resource.bypass_dhcp,
      bypass_dns: new_resource.bypass_dns
    )
    mode 0o644
    action :create
  end

  service "openvpn@#{new_resource.name}" do
    action %i[enable start]
  end

  if new_resource.manage_firewall_rules
    with_run_context :root do
      firewall_rule "openvpn-#{new_resource.name}" do
        port new_resource.port
        source '0.0.0.0/0'
        protocol openvpn_proto.to_sym
        position new_resource.firewall_filter_rule_position
        command :allow
      end

      if new_resource.redirect_gateway
        firewall_rule "openvpn-#{new_resource.name}-postrouting" do
          source new_resource.network  # this line is needed to bypass setting raw IPv6 rule
          raw lazy { "-A POSTROUTING -s #{new_resource.network} -o #{::ChefCookbook::VPN.public_interface} -j MASQUERADE" }
          position new_resource.firewall_nat_rule_position
          command :allow
        end
      end
    end
  end

  client_config_basedir = ::File.join(new_resource.basedir, 'client-config')

  directory client_config_basedir do
    owner new_resource.user
    group new_resource.group
    mode 0o755
    action :create
  end

  client_config_dir_path = ::File.join(client_config_basedir, new_resource.name)

  directory client_config_dir_path do
    owner new_resource.user
    group new_resource.group
    mode 0o755
    action :create
  end

  client_config_file_dir_path = ::File.join(client_config_dir_path, 'files')

  directory client_config_file_dir_path do
    owner new_resource.user
    group new_resource.group
    mode 0o700
    action :create
  end

  base_client_conf_file_name = 'base.conf'
  base_client_conf_file_path = ::File.join(client_config_dir_path,
                                           base_client_conf_file_name)

  template base_client_conf_file_path do
    cookbook 'vpn'
    source 'client.conf.erb'
    owner new_resource.user
    group new_resource.group
    variables(
      fqdn: new_resource.fqdn,
      port: new_resource.port,
      proto: openvpn_proto,
      cipher: openvpn_cipher,
      auth: openvpn_auth
    )
    mode 0o644
    action :create
  end

  make_config_script_path = ::File.join(client_config_dir_path, 'make-config')

  template make_config_script_path do
    cookbook 'vpn'
    source 'make-config.sh.erb'
    owner new_resource.user
    group new_resource.group
    variables(
      key_dir: key_dir_path,
      output_dir: client_config_file_dir_path,
      base_config: base_client_conf_file_path
    )
    mode 0o700
    action :create
  end
end
