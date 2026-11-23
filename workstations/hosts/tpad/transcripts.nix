# Hourly copy of the full Claude, Codex and Antigravity transcripts to Hestia's archive
# (~/agent-transcripts/tpad). The key only reaches rrsync there, which can
# write into that folder and nothing else.
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
      # -F none: no ControlMaster or relaxed host checks from ~/.ssh/config.
      export RSYNC_RSH="ssh -F none -i ${key} -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${knownHosts}"
      # No --delete, so the archive keeps what the agents prune. An agent
      # never run here has no folder yet.
      if [ -d "$HOME/.claude/projects" ]; then
        rsync -a "$HOME/.claude/projects/" mikaelsiidorow@hestia.vpn.miksu.app:claude/
      fi
      if [ -d "$HOME/.codex/sessions" ]; then
        rsync -a "$HOME/.codex/sessions/" mikaelsiidorow@hestia.vpn.miksu.app:codex/
      fi
      # Antigravity keeps a home for the agy CLI and one per T3 provider
      # instance. Copy only the conversations, never its OAuth token. Flat
      # names, since rsync creates only the last folder of the target.
      agy() {
        [ -d "$1" ] || return 0
        rsync -a \
          --include='/brain/***' --include='/conversations/***' \
          --include='/annotations/***' --include='/conversation_summaries.db' \
          --exclude='*' \
          "$1/" "mikaelsiidorow@hestia.vpn.miksu.app:antigravity-$2/"
      }
      agy "$HOME/.gemini/antigravity-cli" cli
      for home in "$HOME"/.t3/*/providers/antigravity/*/antigravity-acp; do
        agy "$home" "t3-$(basename "$(dirname "$home")")"
      done
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
