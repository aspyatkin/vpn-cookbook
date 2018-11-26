resource_name :vpn_server
property :name, String, name_property: true

property :basedir, String, default: '/etc/chef-vpn'
property :user, String, required: true
property :group, String, required: true

property :cert_country, String, required: true
property :cert_province, String, required: true
property :cert_city, String, required: true
property :cert_org, String, required: true
property :cert_email, String, required: true
property :cert_ou, String, required: true

property :cert_key_size, Integer, default: 2048

property :openvpn_port, Integer, default: 1194
property :openvpn_proto, String, default: 'tcp'
property :openvpn_cipher, String, default: 'AES-128-CBC'
property :openvpn_auth, String, default: 'SHA256'
property :openvpn_network, String, required: true

default_action :setup

action :setup do
  %w(
    openvpn
    easy-rsa
  ).each do |pkg_name|
    package pkg_name do
      action :install
    end
  end

  instance = ::ChefCookbook::Instance::Helper.new(node)

  directory new_resource.basedir do
    owner new_resource.user
    group new_resource.group
    mode 0755
    recursive true
    action :create
  end

  ca_dir = ::File.join(new_resource.basedir, new_resource.name)

  execute "create CA directory at #{ca_dir}" do
    command "make-cadir #{ca_dir}"
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.directory?(ca_dir) }
  end

  server_key_dir = 'keys'
  server_key_name = 'server'

  defaults = {
    'KEY_COUNTRY' => new_resource.cert_country,
    'KEY_PROVINCE' => new_resource.cert_province,
    'KEY_CITY' => new_resource.cert_city,
    'KEY_ORG' => new_resource.cert_org,
    'KEY_EMAIL' => new_resource.cert_email,
    'KEY_OU' => new_resource.cert_ou,
    'KEY_NAME' => server_key_name,
    'KEY_DIR' => "$EASY_RSA/#{server_key_dir}",
    'KEY_SIZE' => new_resource.cert_key_size
  }

  vars_file = ::File.join(ca_dir, 'vars')

  defaults.each do |key, val|
    replace_or_add "adjust #{key} in #{vars_file}" do
      path vars_file
      pattern ::Regexp.new("^export #{key}=.*$")
      line "export #{key}=#{val.kind_of?(::Numeric) ? val.to_s : val.dump}"
      replace_only true
      ignore_missing false
      action :edit
    end
  end

  if node['platform'] == 'ubuntu' && node['platform_version'].to_f >= 18.04
    execute "Fix openssl.cnf at #{ca_dir}" do
      cwd ca_dir
      command 'cp ./openssl-1.0.0.cnf ./openssl.cnf'
      user new_resource.user
      group new_resource.group
      action :run
      not_if { ::File.exist?(::File.join(ca_dir, 'openssl.cnf')) }
    end
  end

  key_dir = ::File.join(ca_dir, server_key_dir)

  bash "clean CA key directory at #{ca_dir}" do
    cwd ca_dir
    code <<-EOH
      source ./vars
      ./clean-all
      EOH
    user instance.user
    group instance.group
    action :run
    not_if { ::Dir.exist?(key_dir) && !::Dir.empty?(key_dir) }
  end

  ca_crt_file = ::File.join(key_dir, 'ca.crt')
  ca_key_file = ::File.join(key_dir, 'ca.key')

  bash "initialize CA at #{ca_dir}" do
    cwd ca_dir
    code <<-EOH
      source ./vars
      ./build-ca --batch
      EOH
    user instance.user
    group instance.group
    action :run
    not_if { ::File.exist?(ca_crt_file) && ::File.exist?(ca_key_file) }
  end

  server_crt_file = ::File.join(key_dir, "#{server_key_name}.crt")
  server_key_file = ::File.join(key_dir, "#{server_key_name}.key")

  bash "build key server at #{ca_dir}" do
    cwd ca_dir
    code <<-EOH
      source ./vars
      ./build-key-server --batch #{server_key_name}
      EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(server_crt_file) && ::File.exist?(server_key_file) }
  end

  dh_key_file = ::File.join(key_dir, "dh#{new_resource.cert_key_size}.pem")

  bash "build dh key at #{ca_dir}" do
    cwd ca_dir
    code <<-EOH
      source ./vars
      ./build-dh
      EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(dh_key_file) }
  end

  ta_key_file = ::File.join(key_dir, 'ta.key')

  bash "build ta key at #{ca_dir}" do
    cwd ca_dir
    code <<-EOH
      openvpn --genkey --secret #{server_key_dir}/ta.key
      EOH
    user instance.user
    group instance.group
    action :run
    not_if { ::File.exist?(ta_key_file) }
  end

  openvpn_basedir = ::File.join('/etc', 'openvpn')

  openvpn_server_basedir = ::File.join(openvpn_basedir, new_resource.name)

  directory openvpn_server_basedir do
    owner instance.root
    group node['root_group']
    mode 0755
    action :create
  end

  client_dir = ::File.join(openvpn_server_basedir, 'clients')

  directory client_dir do
    owner instance.root
    group node['root_group']
    mode 0755
    action :create
  end

  [
    'ca.crt',
    'ca.key',
    "#{server_key_name}.crt",
    "#{server_key_name}.key",
    "dh#{new_resource.cert_key_size}.pem",
    "ta.key"
  ].each do |file_name|
    file ::File.join(openvpn_server_basedir, file_name) do
      content lazy { ::IO.read(::File.join(key_dir, file_name)) }
      owner instance.root
      group node['root_group']
      mode 0600
      sensitive true
      action :create
    end
  end

  server_conf_file = ::File.join(openvpn_basedir, "#{new_resource.name}.conf")

  require 'ip'
  network = ::IP.new(new_resource.openvpn_network)

  template server_conf_file do
    cookbook 'vpn'
    source 'server.conf.erb'
    owner instance.root
    group node['root_group']
    variables(
      port: new_resource.openvpn_port,
      proto: new_resource.openvpn_proto,
      ta_key: ::File.join(new_resource.name, 'ta.key'),
      cipher: new_resource.openvpn_cipher,
      auth: new_resource.openvpn_auth,
      ca: ::File.join(new_resource.name, 'ca.crt'),
      cert: ::File.join(new_resource.name, 'server.crt'),
      key: ::File.join(new_resource.name, 'server.key'),
      dh: ::File.join(new_resource.name, "dh#{new_resource.cert_key_size}.pem"),
      network: network,
      ipp_file: ::File.join(new_resource.name, 'ipp.txt'),
      client_dir: ::File.join(new_resource.name, 'clients'),
      status_file: ::File.join('/var', 'log', 'openvpn', "#{new_resource.name}-status.log")
    )
    mode 0644
    action :create
  end

  service "openvpn@#{new_resource.name}" do
    action [:enable, :start]
  end

  # sysctl 'net.ipv4.ip_forward' do
  #   value 1
  #   action :apply
  # end

end
