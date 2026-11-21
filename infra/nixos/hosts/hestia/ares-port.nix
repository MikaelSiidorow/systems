{ config, pkgs, ... }:
let
  # Ares keeps Wake-on-LAN armed, so its NIC holds a 10 Mbps link that blinks
  # all night. pc_plug shows whether the PC is on: off draws 0-3 W, on draws
  # 60 W or more. Open Cerberus port lan1 when the PC draws power and close it
  # after a few minutes at standby, so the light only shows while ares runs.
  # Pressing the power button raises the reading during POST, well before
  # Windows brings up the network.
  router = "192.168.67.1";
  port = "lan1";
  onWatts = 20;
  offWatts = 10;
  offAfterSeconds = 180;
  # A router reboot or network reload brings the port back up; reassert it.
  reassertSeconds = 600;
  # The plug reports every 10-40 s. Without readings, open the port so a
  # Zigbee outage cannot leave a running ares offline.
  staleSeconds = 300;

  aresPort = pkgs.writeShellApplication {
    name = "ares-port";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      mosquitto
      openssh
    ];
    text = ''
      applied=""
      applied_at=0
      low_since=""
      last_seen=$(date +%s)

      set_port() {
        if timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=5 \
          -i ${config.sops.secrets.router-deploy-ssh-key.path} \
          root@${router} "ip link set ${port} $1"; then
          [ "$applied" = "$1" ] || echo "${port} $1"
          applied=$1
          applied_at=$(date +%s)
        else
          echo "failed to set ${port} $1" >&2
        fi
      }

      if [ $# -gt 0 ]; then
        set_port "$1"
        exit
      fi

      decide() {
        local now=$1 power=$2
        if [ -n "$power" ]; then
          last_seen=$now
        elif (( now - last_seen >= ${toString staleSeconds} )); then
          low_since=""
          [ "$applied" = up ] || set_port up
          return
        fi
        if [ -n "$power" ]; then
          if (( power >= ${toString onWatts} )); then
            low_since=""
            [ "$applied" = up ] || set_port up
            return
          fi
          if (( power < ${toString offWatts} )); then
            low_since=''${low_since:-$now}
          else
            low_since=""
          fi
        fi
        if [ -n "$low_since" ] && (( now - low_since >= ${toString offAfterSeconds} )); then
          if [ "$applied" != down ] || (( now - applied_at >= ${toString reassertSeconds} )); then
            set_port down
          fi
        fi
      }

      exec 3< <(mosquitto_sub -h 127.0.0.1 -t zigbee2mqtt/pc_plug)
      while true; do
        power=""
        if IFS= read -r -t 60 msg <&3; then
          power=$(jq -r '.power // empty | floor' <<<"$msg" 2>/dev/null || true)
        elif (( $? <= 128 )); then
          echo "mosquitto_sub exited" >&2
          exit 1
        fi
        decide "$(date +%s)" "$power"
      done
    '';
  };
in
{
  systemd.services.ares-port = {
    description = "Close Cerberus lan1 while ares is powered off";
    wantedBy = [ "multi-user.target" ];
    after = [
      "mosquitto.service"
      "network-online.target"
    ];
    # Wants, not Requires: a broker stop must not stop the watcher for good.
    # With no broker mosquitto_sub exits and Restart= retries until it is back.
    wants = [
      "mosquitto.service"
      "network-online.target"
    ];
    serviceConfig = {
      ExecStart = "${aresPort}/bin/ares-port";
      # Fail open: however the watcher stops, a running ares must not stay
      # offline.
      ExecStopPost = "${aresPort}/bin/ares-port up";
      Restart = "always";
      RestartSec = 10;
    };
  };

  programs.ssh.knownHosts.cerberus = {
    hostNames = [ router ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINs1I/wmdo31Al1vl9pvu4UbhjFKL+F4zv9SwOIFTrZV";
  };
}
