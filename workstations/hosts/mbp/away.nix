# `away`: keep agents running while I'm gone. Locks the screen and holds a
# caffeinate assertion (on the charger only) until I unlock, capped at 12 h.
# The managed power settings stay untouched.
{ pkgs, ... }:
let
  away = pkgs.writeShellApplication {
    name = "away";
    text = ''
      locked() {
        [[ $(/usr/sbin/ioreg -n Root -d1 -a) == *CGSSessionScreenIsLocked* ]]
      }

      if [ "''${1:-}" = --watch ]; then
        # caffeinate exits with this watcher. -s: only on AC. -t: 12 h cap.
        /usr/bin/caffeinate -s -t 43200 -w $$ &
        # Wait up to a minute for the lock, then until the unlock.
        for _ in $(seq 30); do
          locked && break
          sleep 2
        done
        while locked; do sleep 10; done
        exit 0
      fi

      nohup "$0" --watch >/dev/null 2>&1 &
      # Turning the display off locks it under the managed lock policy.
      /usr/bin/pmset displaysleepnow
    '';
  };
in
{
  home.packages = [ away ];

  # Raycast script command. Add this folder once in Raycast: Settings >
  # Extensions > Script Commands > Add Directories.
  home.file.".config/raycast/script-commands/away.sh".source = pkgs.writeShellScript "raycast-away" ''
    # @raycast.schemaVersion 1
    # @raycast.title Away
    # @raycast.mode silent
    # @raycast.icon 🌙
    # @raycast.packageName Away
    exec ${away}/bin/away
  '';
}
