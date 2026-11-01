# Dewclaw module shared by both routers; see drop-tcp-ip-options.nft.
{
  # firewall4 includes /etc/nftables.d/*.nft inside its inet fw4 table.
  etc."nftables.d/20-drop-tcp-ip-options.nft".text = builtins.readFile ./drop-tcp-ip-options.nft;

  # reload_config only restarts services whose UCI changed, so a reload-only
  # deploy would leave the new include inactive.
  deploySteps.firewallReload = {
    priority = 95;
    apply = "/etc/init.d/firewall reload";
  };
}
