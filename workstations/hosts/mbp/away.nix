# `away`: keep agents running while I'm gone. Holds a caffeinate assertion
# (on the charger only, capped at 12 h) and locks the screen. The managed
# power settings stay untouched; unplugging or `away stop` ends it.
{ config, pkgs, ... }:
let
  away = pkgs.writeShellApplication {
    name = "away";
    text = ''
      pidfile="${config.xdg.stateHome}/away/caffeinate.pid"

      stop() {
        if pid=$(cat "$pidfile" 2>/dev/null) && [ "$(/bin/ps -o comm= -p "$pid" 2>/dev/null)" = /usr/bin/caffeinate ]; then
          kill "$pid"
          echo "Stopped keeping the Mac awake."
        else
          echo "Away was not on."
        fi
        rm -f "$pidfile"
      }

      case "''${1:-start}" in
        start)
          stop >/dev/null
          mkdir -p "$(dirname "$pidfile")"
          # -s: only while on AC power. -t: give up after 12 hours.
          nohup /usr/bin/caffeinate -s -t 43200 >/dev/null 2>&1 &
          echo $! >"$pidfile"
          # Turning the display off locks it under the managed lock policy.
          /usr/bin/pmset displaysleepnow
          ;;
        stop) stop ;;
        *)
          echo "usage: away [start|stop]" >&2
          exit 2
          ;;
      esac
    '';
  };

  # Raycast script commands. Add this folder once in Raycast: Settings >
  # Extensions > Script Commands > Add Directories.
  raycastScript =
    title: icon: arg:
    pkgs.writeShellScript "raycast-${arg}" ''
      # @raycast.schemaVersion 1
      # @raycast.title ${title}
      # @raycast.mode silent
      # @raycast.icon ${icon}
      # @raycast.packageName Away
      exec ${away}/bin/away ${arg}
    '';
in
{
  home.packages = [ away ];

  home.file = {
    ".config/raycast/script-commands/away.sh".source = raycastScript "Away" "🌙" "start";
    ".config/raycast/script-commands/back.sh".source = raycastScript "Back" "☀️" "stop";
  };
}
