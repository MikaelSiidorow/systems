{ config, lib, ... }:
{
  # GTX 1060 (Pascal). Headless agents run Godot render checks and screenshots
  # under gamescope, which needs a Vulkan driver; nouveau without Mesa has none.
  # The 590+ branches dropped Pascal, so pin the 580 legacy branch.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "nvidia-kernel-modules"
      "nvidia-settings"
    ];
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    # Pascal has no open kernel module.
    open = false;
    modesetting.enable = true;
    nvidiaSettings = false;
  };
}
