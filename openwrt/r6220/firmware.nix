{
  openwrt-imagebuilder,
  pkgs,
}:
let
  release = "25.12.5";
  profiles = openwrt-imagebuilder.lib.profiles {
    inherit pkgs release;
  };
in
openwrt-imagebuilder.lib.build (
  profiles.identifyProfile "netgear_r6220"
  // {
    inherit release;
    extraImageName = "nix";

    # Keep this list authoritative. Dewclaw package deployment is disabled
    # until its OpenWrt 25.12/apk support is ready.
    packages = [
      "htop"
      "https-dns-proxy"
      "luci-app-https-dns-proxy"
      "luci-mod-rpc"
      "luci-ssl"
      "tcpdump"
    ];

    # Only public, non-secret bootstrap state belongs in the firmware image.
    # Files included here are copied into the world-readable Nix store.
    files = pkgs.symlinkJoin {
      name = "r6220-openwrt-files";
      paths = [
        ../files
        ./files
      ];
    };
  }
)
