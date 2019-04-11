resource_name :vpn_connect
property :name, String, name_property: true
property :client_name, String, default: 'client'
property :config, String, required: true

default_action :create

action :create do
  instance = ::ChefCookbook::Instance::Helper.new(node)

  package 'openvpn'

  file "/etc/openvpn/#{new_resource.client_name}.conf" do
    owner instance.root
    group node['root_group']
    mode 0600
    content new_resource.config
    sensitive true
    action :create
  end

  service "openvpn@#{new_resource.client_name}" do
    action [:start, :enable]
  end
end
