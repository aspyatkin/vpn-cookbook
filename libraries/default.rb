module ChefCookbook
  module VPN
    def self.public_interface
      `ip route | grep default | awk '{print $5}'`.strip
    end
  end
end
