# Hourly copy of the full Claude and Codex transcripts to Hestia's archive
# (~/agent-transcripts/tpad). The key only reaches rrsync there, which can add
# and update files in that folder and nothing else.
{ config, pkgs, ... }:
let
  key = config.sops.secrets."ssh/transcripts_key".path;
  knownHosts = pkgs.writeText "hestia-known-hosts" ''
    hestia.vpn.miksu.app ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5EnbyFToqAoGfMv3vLl0pCr41ZQ9+F9U0zhQecvq7t
  '';
  push = pkgs.writeShellApplication {
    name = "transcripts-push";
    runtimeInputs = [
      pkgs.openssh
      pkgs.rsync
    ];
    text = ''
      export RSYNC_RSH="ssh -i ${key} -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=${knownHosts}"
      # No --delete, so the archive keeps what the agents prune.
      rsync -a "$HOME/.claude/projects/" mikaelsiidorow@hestia.vpn.miksu.app:claude/
      rsync -a "$HOME/.codex/sessions/" mikaelsiidorow@hestia.vpn.miksu.app:codex/
    '';
  };
in
{
  agents.keepTranscripts = true;

  sops.secrets."ssh/transcripts_key".sopsFile = ../../secrets/transcripts.yaml;

  home.packages = [ push ];

  systemd.user.services.transcripts-push = {
    Unit = {
      Description = "Copy agent transcripts to Hestia";
      After = [ "sops-nix.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${push}/bin/transcripts-push";
    };
  };

  # Persistent catches up after the laptop was off or asleep; offline runs
  # just fail until the next hour.
  systemd.user.timers.transcripts-push = {
    Unit.Description = "Copy agent transcripts to Hestia hourly";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
