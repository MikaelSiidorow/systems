# Keep the Mac awake on the charger so agents and the network keep running
# while it is locked. The display still sleeps on its own timer. Battery
# settings are left alone.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.power;

  # pmset's disablesleep has no AC or battery profile, so follow the power
  # source: on AC the lid stops sleeping the Mac, on battery it sleeps as usual.
  lidFollowsPower = pkgs.writeShellScript "lid-follows-power" ''
    want=0
    /usr/bin/pmset -g ps | /usr/bin/head -1 | /usr/bin/grep -q "'AC Power'" && want=1
    current=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ { print $2 }')
    [ "$current" = "$want" ] || /usr/bin/pmset -a disablesleep "$want"
  '';
in
{
  options.power = {
    stayAwakeOnAC = lib.mkEnableOption "staying awake on AC power while the display is off";
    ignoreLidOnAC = lib.mkEnableOption "staying awake on AC power with the lid closed";
  };

  config = {
    # nix-darwin's power.sleep.computer sets AC and battery together, so call
    # pmset for the AC profile only. 1 minute is the macOS default: idle sleep
    # follows display sleep. Without the daemon, clear disablesleep so turning
    # the option off cannot leave the lid ignored.
    system.activationScripts.postActivation.text = ''
      /usr/bin/pmset -c sleep ${if cfg.stayAwakeOnAC then "0" else "1"}
      ${if cfg.ignoreLidOnAC then lidFollowsPower else "/usr/bin/pmset -a disablesleep 0"}
    '';

    # Polled: launchd has no power-source trigger. After unplugging with the
    # lid closed, the Mac sleeps within one interval.
    launchd.daemons.lid-follows-power = lib.mkIf cfg.ignoreLidOnAC {
      serviceConfig = {
        ProgramArguments = [ "${lidFollowsPower}" ];
        RunAtLoad = true;
        StartInterval = 5;
      };
    };
  };
}
