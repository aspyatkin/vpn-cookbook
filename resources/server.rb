resource_name :vpn_server
property :name, String, name_property: true
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
end
