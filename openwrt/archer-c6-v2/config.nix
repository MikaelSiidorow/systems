{ lib, ... }:
{
  openwrt.archer-c6-v2 = {
    deploy = {
      host = "192.168.67.2";
      user = "root";
      rollbackTimeout = 90;
    };

    # OpenWrt 25.12 uses apk. Firmware construction, not Dewclaw's opkg-based
    # package step, owns the package set.
    deploySteps.packages = {
      copy = lib.mkForce "";
      apply = lib.mkForce "";
    };

    # The encrypted key must exist before this configuration can be deployed.
    sopsSecrets = ../secrets/openwrt.yaml;

    uci.retain = [
      "attendedsysupgrade"
      "dropbear"
      "firewall"
      "luci"
      "rpcd"
      "ubootenv"
      "uhttpd"
    ];

    uci.settings = {
      # Captured after configuring the Archer as a LAN-to-LAN access point.
      network = {
        device = [
          {
            name = "br-lan";
            type = "bridge";
            ports = [ "eth0.1" ];
          }
        ];

        globals.globals = {
          dhcp_default_duid = "000446fb98a0de8f457a9ef7d4dc973d8ca9";
          ula_prefix = "fd4e:3480:896b::/48";
          packet_steering = "1";
        };

        interface = {
          loopback = {
            device = "lo";
            proto = "static";
            ipaddr = [ "127.0.0.1/8" ];
          };
          lan = {
            device = "br-lan";
            proto = "static";
            ip6assign = "60";
            ipaddr = [ "192.168.67.2/24" ];
            multipath = "off";
            gateway = "192.168.67.1";
            dns = [ "192.168.67.1" ];
          };
          wan = {
            device = "eth0.2";
            proto = "dhcp";
          };
          wan6 = {
            device = "eth0.2";
            proto = "dhcpv6";
          };
        };

        switch = [
          {
            name = "switch0";
            reset = "1";
            enable_vlan = "1";
          }
        ];
        switch_vlan = [
          {
            device = "switch0";
            vlan = "1";
            ports = "2 3 4 5 0t";
          }
          {
            device = "switch0";
            vlan = "2";
            ports = "1 0t";
          }
        ];
      };

      dhcp = {
        dnsmasq = [
          {
            domainneeded = "1";
            boguspriv = "1";
            filterwin2k = "0";
            localise_queries = "1";
            rebind_protection = "1";
            rebind_localhost = "1";
            local = "/home.arpa/";
            domain = "home.arpa";
            expandhosts = "1";
            nonegcache = "0";
            cachesize = "1000";
            authoritative = "1";
            readethers = "1";
            leasefile = "/tmp/dhcp.leases";
            resolvfile = "/tmp/resolv.conf.d/resolv.conf.auto";
            nonwildcard = "1";
            localservice = "1";
            ednspacket_max = "1232";
            filter_aaaa = "0";
            filter_a = "0";
          }
        ];

        dhcp = {
          lan = {
            interface = "lan";
            start = "100";
            limit = "150";
            leasetime = "12h";
            dhcpv4 = "disabled";
            ignore = "1";
          };
          wan = {
            interface = "wan";
            ignore = "1";
          };
        };

        odhcpd.odhcpd = {
          maindhcp = "0";
          leasefile = "/tmp/odhcpd.leases";
          leasetrigger = "/usr/sbin/odhcpd-update";
          loglevel = "4";
          piodir = "/tmp/odhcpd-piodir";
          hostsdir = "/tmp/hosts";
        };
      };

      system = {
        system = [
          {
            hostname = "hermes";
            timezone = "GMT0";
            zonename = "UTC";
            ttylogin = "0";
            log_size = "128";
            urandom_seed = "0";
          }
        ];

        timeserver.ntp = {
          enabled = "1";
          enable_server = "0";
          server = [
            "0.openwrt.pool.ntp.org"
            "1.openwrt.pool.ntp.org"
            "2.openwrt.pool.ntp.org"
            "3.openwrt.pool.ntp.org"
          ];
        };

        led = {
          led_lan = {
            name = "LAN";
            sysfs = "green:lan";
            trigger = "switch0";
            port_mask = "0x3c";
          };
          led_wan = {
            name = "WAN";
            sysfs = "green:wan";
            trigger = "switch0";
            port_mask = "0x02";
          };
        };
      };

      wireless = {
        wifi-device = {
          radio0 = {
            type = "mac80211";
            path = "pci0000:00/0000:00:00.0";
            band = "5g";
            channel = "36";
            htmode = "VHT80";
            country = "FI";
            cell_density = "0";
          };
          radio1 = {
            type = "mac80211";
            path = "platform/ahb/18100000.wmac";
            band = "2g";
            channel = "auto";
            htmode = "HT20";
            country = "FI";
            cell_density = "0";
          };
        };

        wifi-iface = {
          default_radio0 = {
            device = "radio0";
            network = "lan";
            mode = "ap";
            ssid = "Mythos";
            encryption = "sae-mixed";
            key._secret = "openwrt_archer_wifi";
            ocv = "0";
          };
          default_radio1 = {
            device = "radio1";
            network = "lan";
            mode = "ap";
            ssid = "Mythos";
            encryption = "sae-mixed";
            key._secret = "openwrt_archer_wifi";
            ocv = "0";
          };
        };
      };
    };
  };
}
