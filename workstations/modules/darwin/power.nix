# Keep the Mac awake on the charger so agents and the network keep running
# while it is locked. The display still sleeps on its own timer, and closing
# the lid still sleeps the Mac. Battery settings are left alone.
{ config, lib, ... }:
{
  options.power.stayAwakeOnAC = lib.mkEnableOption "staying awake on AC power while the display is off";

  # nix-darwin's power.sleep.computer sets AC and battery together, so call
  # pmset for the AC profile only. 1 minute is the macOS default: idle sleep
  # follows display sleep.
  config.system.activationScripts.postActivation.text = ''
    /usr/bin/pmset -c sleep ${if config.power.stayAwakeOnAC then "0" else "1"}
  '';
}
