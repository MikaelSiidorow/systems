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
  profiles.identifyProfile "tplink_archer-c6-v2"
  // {
    inherit release;
    extraImageName = "nix";

    # The Archer has only 8 MB of flash. Keep the official package set and
    # install no optional services on this access point.
    packages = [ ];

    # Public bootstrap access only; private keys never enter the Nix store.
    files = ../files;
  }
)
