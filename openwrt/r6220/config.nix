{ config, lib, ... }:
let
  namedSectionNames =
    package:
    lib.concatMap (sections: if builtins.isAttrs sections then builtins.attrNames sections else [ ]) (
      builtins.attrValues package
    );

  sectionNamesAreUnique =
    package:
    let
      names = namedSectionNames package;
    in
    builtins.length names == builtins.length (lib.unique names);
in
{
  openwrt.r6220 = {
    deploy = {
      # Use the fixed LAN address so deployment does not depend on local DNS.
      host = "192.168.67.1";
      user = "root";
      rollbackTimeout = 90;
    };

    # OpenWrt 25.12 uses apk, while Dewclaw main still deploys packages with
    # opkg. The firmware image above is the sole owner of installed packages.
    deploySteps.packages = {
      copy = lib.mkForce "";
      apply = lib.mkForce "";
    };

    # UCI section names share one namespace per package, even across section
    # types. Catch conflicts during evaluation instead of on the router.
    assertions = lib.mapAttrsToList (packageName: package: {
      assertion = sectionNamesAreUnique package;
      message = "UCI package ${packageName} contains duplicate named sections";
    }) config.openwrt.r6220.uci.settings;

    # Keep configuration that we have not intentionally made declarative.
    uci.retain = [
      "attendedsysupgrade"
      "dropbear"
      "luci"
      "rpcd"
      "ubihealthd"
      "uhttpd"
    ];

    uci.settings = {
      # dnsmasq remains the LAN resolver but sends every upstream query to the
      # local Mullvad DoH proxy. The canary domains discourage automatic
      # browser DoH and iCloud Private Relay from bypassing router DNS.
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
            noresolv = "1";
            server = [
              "/mask.icloud.com/"
              "/mask-h2.icloud.com/"
              "/use-application-dns.net/"
              "127.0.0.1#5053"
            ];
          }
        ];

        dhcp = {
          lan = {
            interface = "lan";
            start = "100";
            limit = "150";
            leasetime = "12h";
            dhcpv4 = "server";
            dhcpv6 = "server";
            ra = "server";
            ra_slaac = "1";
            ra_flags = [
              "managed-config"
              "other-config"
            ];
          };
          wan = {
            interface = "wan";
            ignore = "1";
          };
        };

        host = {
          chromecast = {
            name = "chromecast";
            mac = "1c:53:f9:6a:c8:04";
            ip = "192.168.67.116";
          };
          hestia = {
            name = "hestia";
            mac = "70:85:c2:a4:50:c2";
            ip = "192.168.67.170";
          };
          roborock = {
            name = "roborock";
            mac = "24:9e:7d:11:d5:0e";
            ip = "192.168.67.107";
          };
          # This is the Ray's Wi-Fi interface. Replace the MAC if the soundbar
          # is later moved to Ethernet; its hostname and address can stay put.
          sonos_ray_wifi = {
            name = "sonos-ray";
            mac = "74:ca:60:82:50:62";
            ip = "192.168.67.220";
          };
        };

        domain = {
          cerberus = {
            name = "cerberus.home.arpa";
            ip = "192.168.67.1";
          };
          hermes = {
            name = "hermes.home.arpa";
            ip = "192.168.67.2";
          };
          hestia_dns = {
            name = "hestia.home.arpa";
            ip = "192.168.67.170";
          };
          ha = {
            name = "ha.home.arpa";
            ip = "192.168.67.170";
          };
          ha_public = {
            name = "ha.miksu.app";
            ip = "192.168.67.170";
          };
          zigbee = {
            name = "zigbee.home.arpa";
            ip = "192.168.67.170";
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

      # Captured from the working firewall after enabling hardware flow
      # offloading. Dewclaw replaces declared UCI packages in full.
      firewall = {
        defaults = [
          {
            input = "REJECT";
            output = "ACCEPT";
            forward = "REJECT";
            synflood_protect = "1";
            flow_offloading = "1";
            flow_offloading_hw = "1";
          }
        ];

        zone = [
          {
            name = "lan";
            network = [ "lan" ];
            input = "ACCEPT";
            output = "ACCEPT";
            forward = "ACCEPT";
          }
          {
            name = "wan";
            network = [
              "wan"
              "wan6"
            ];
            input = "REJECT";
            output = "ACCEPT";
            forward = "DROP";
            masq = "1";
            mtu_fix = "1";
          }
        ];

        forwarding = [
          {
            src = "lan";
            dest = "wan";
          }
        ];

        rule = [
          {
            name = "Allow-DHCP-Renew";
            src = "wan";
            proto = "udp";
            dest_port = "68";
            target = "ACCEPT";
            family = "ipv4";
          }
          {
            name = "Allow-Ping";
            src = "wan";
            proto = "icmp";
            icmp_type = "echo-request";
            family = "ipv4";
            target = "ACCEPT";
          }
          {
            name = "Allow-IGMP";
            src = "wan";
            proto = "igmp";
            family = "ipv4";
            target = "ACCEPT";
          }
          {
            name = "Allow-DHCPv6";
            src = "wan";
            proto = "udp";
            dest_port = "546";
            family = "ipv6";
            target = "ACCEPT";
          }
          {
            name = "Allow-MLD";
            src = "wan";
            proto = "icmp";
            src_ip = "fe80::/10";
            icmp_type = [
              "130/0"
              "131/0"
              "132/0"
              "143/0"
            ];
            family = "ipv6";
            target = "ACCEPT";
          }
          {
            name = "Allow-ICMPv6-Input";
            src = "wan";
            proto = "icmp";
            icmp_type = [
              "echo-request"
              "echo-reply"
              "destination-unreachable"
              "packet-too-big"
              "time-exceeded"
              "bad-header"
              "unknown-header-type"
              "router-solicitation"
              "neighbour-solicitation"
              "router-advertisement"
              "neighbour-advertisement"
            ];
            limit = "1000/sec";
            family = "ipv6";
            target = "ACCEPT";
          }
          {
            name = "Allow-ICMPv6-Forward";
            src = "wan";
            dest = "*";
            proto = "icmp";
            icmp_type = [
              "echo-request"
              "echo-reply"
              "destination-unreachable"
              "packet-too-big"
              "time-exceeded"
              "bad-header"
              "unknown-header-type"
            ];
            limit = "1000/sec";
            family = "ipv6";
            target = "ACCEPT";
          }
          {
            name = "Allow-IPSec-ESP";
            src = "wan";
            dest = "lan";
            proto = "esp";
            target = "ACCEPT";
          }
          {
            name = "Allow-ISAKMP";
            src = "wan";
            dest = "lan";
            dest_port = "500";
            proto = "udp";
            target = "ACCEPT";
          }
        ];
      };

      "https-dns-proxy" = {
        main.config = {
          canary_domains_icloud = "1";
          canary_domains_mozilla = "1";

          # dnsmasq is declared above; do not mutate it from the init script.
          dnsmasq_config_update = "";
          force_dns = "0";
          notrack_dns = "1";
          force_dns_port = [
            "53"
            "853"
          ];
          force_dns_src_interface = [ "lan" ];
          procd_trigger_wan6 = "0";
          heartbeat_domain = "heartbeat.mossdef.org";
          heartbeat_sleep_timeout = "10";
          heartbeat_wait_timeout = "10";
          user = "nobody";
          group = "nogroup";
          listen_addr = "127.0.0.1";
          force_ip_family = "auto";
        };

        "https-dns-proxy".mullvad = {
          bootstrap_dns = "194.242.2.2";
          resolver_url = "https://base.dns.mullvad.net/dns-query";
          listen_port = "5053";
        };
      };

      # Captured from the official OpenWrt 25.12.5 first boot. The generated
      # DUID, ULA prefix, DSA port names, and radio paths belong to this device.
      network = {
        device = [
          {
            name = "br-lan";
            type = "bridge";
            ports = [
              "lan1"
              "lan2"
              "lan3"
              "lan4"
            ];
          }
        ];

        globals.globals = {
          dhcp_default_duid = "0004e494a05858a94c929460ea3e3f47fab9";
          ula_prefix = "fd4e:b7fd:9cf8::/48";
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
            ipaddr = [ "192.168.67.1/24" ];
            ip6assign = "60";
          };
          wan = {
            device = "wan";
            proto = "dhcp";
          };
          wan6 = {
            device = "wan";
            proto = "dhcpv6";
          };
        };
      };

      system = {
        system = [
          {
            hostname = "cerberus";
            timezone = "GMT0";
            zonename = "UTC";
            ttylogin = "0";
            log_size = "128";
            urandom_seed = "0";
            compat_version = "1.1";
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

        led.led_wan = {
          name = "wan";
          sysfs = "green:wan";
          trigger = "netdev";
          mode = "link tx rx";
          dev = "wan";
        };
      };

      wireless = {
        wifi-device = {
          radio0 = {
            type = "mac80211";
            path = "1e140000.pcie/pci0000:00/0000:00:02.0/0000:02:00.0";
            band = "2g";
            channel = "1";
            htmode = "HT20";
          };
          radio1 = {
            type = "mac80211";
            path = "1e140000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0";
            band = "5g";
            channel = "36";
            htmode = "VHT80";
          };
        };

        wifi-iface = {
          default_radio0 = {
            device = "radio0";
            network = "lan";
            mode = "ap";
            ssid = "OpenWrt";
            encryption = "none";
            disabled = "1";
          };
          default_radio1 = {
            device = "radio1";
            network = "lan";
            mode = "ap";
            ssid = "OpenWrt";
            encryption = "none";
            disabled = "1";
          };
        };
      };
    };

    # TODO: After adding encrypted router secrets to secrets/openwrt.yaml:
    # sopsSecrets = ../secrets/openwrt.yaml;
    # users.root.hashedPasswordSecret = "openwrt_r6220_root_password_hash";
  };
}
