resource_name :vpn_client
property :name, String, name_property: true

property :basedir, String, default: '/etc/chef-vpn'
property :user, String, required: true
property :group, String, required: true
property :server, String, required: true
property :ipv4_address, String, required: true

default_action :create

action :create do
  instance = ::ChefCookbook::Instance::Helper.new(node)

  ca_dir_path = ::File.join(new_resource.basedir, 'server', new_resource.server)
  key_dir_name = 'keys'
  key_dir_path = ::File.join(ca_dir_path, key_dir_name)

  client_crt_file_name = "#{new_resource.name}.crt"
  client_key_file_name = "#{new_resource.name}.key"

  client_crt_file_path = ::File.join(key_dir_path, client_crt_file_name)
  client_key_file_path = ::File.join(key_dir_path, client_key_file_name)

  bash "generate client #{new_resource.name} key at #{ca_dir_path}" do
    cwd ca_dir_path
    code <<-EOH
      source ./vars
      ./build-key --batch #{new_resource.name}
      EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(client_crt_file_path) && ::File.exist?(client_key_file_path) }
  end

  client_config_dir_path = ::File.join(new_resource.basedir, 'client-config', new_resource.server)
  client_config_file_dir_path = ::File.join(client_config_dir_path, 'files')

  client_ovpn_file_name = "#{new_resource.name}.ovpn"
  client_ovpn_file_path = ::File.join(client_config_file_dir_path, client_ovpn_file_name)

  bash "generate client #{new_resource.name} config file at #{client_config_dir_path}" do
    cwd client_config_dir_path
    code <<-EOH
      ./make-config #{new_resource.name}
      EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::File.exist?(client_ovpn_file_path) }
  end

  client_opts_file = ::File.join('/etc', 'openvpn', new_resource.server, 'clients', new_resource.name)

  require 'ip'

  template client_opts_file do
    cookbook 'vpn'
    source 'client_opts.erb'
    owner instance.root
    group node['root_group']
    variables(
      ipv4_address: new_resource.ipv4_address,
      network: ::IP.new(resources("vpn_server[#{new_resource.server}]").network)
    )
    mode 0644
    action :create
  end
end
