# Git configuration - platform-agnostic
{ config, pkgs, ... }:
let
  signingEmail = "mikael@siidorow.com";
  signingKeyPath = "${config.home.homeDirectory}/.ssh/git_signing_key";
  allowedSignersPath = "${config.home.homeDirectory}/.ssh/allowed_signers";
  signingPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtyePmG2oyS5n9bOWraUq3bci8L2jNJg7xiB8gR42PX mikael@siidorow.com git signing";
in
{
  programs.git = {
    enable = true;
    attributes = [ "* merge=mergiraf" ];
    ignores = [
      ".DS_Store"
      "CLAUDE.md"
      ".claude"
      ".codex"
      ".github/copilot-instructions.md"
      "todo.md"
    ];
    settings = {
      user = {
        name = "Mikael Siidorow";
        email = signingEmail;
        signingKey = signingKeyPath;
      };
      init.defaultBranch = "main";
      core = {
        autocrlf = "input";
        editor = "${pkgs.vim}/bin/vim";
        # Big repos: skip the full-tree lstat, so a concurrent status can't
        # write a stale index mid-rebase. Daemon is macOS/Windows only.
        fsmonitor = pkgs.stdenv.isDarwin;
        untrackedCache = true;
      };
      branch.sort = "-committerdate";
      merge.conflictstyle = "zdiff3";
      pull.ff = "only";
      rebase.autoStash = true;
      rerere.enabled = true;
      commit.gpgsign = true;
      tag.gpgSign = true;
      gpg = {
        format = "ssh";
        ssh = {
          allowedSignersFile = allowedSignersPath;
          program = "${pkgs.openssh}/bin/ssh-keygen";
        };
      };

      "merge \"mergiraf\"" = {
        name = "mergiraf";
        driver = "${pkgs.mergiraf}/bin/mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L";
      };
    };
  };

  # Managed to neutralize stale ~/.gitconfig files during migration. The real
  # config is written by Home Manager to $XDG_CONFIG_HOME/git/config.
  home.file = {
    ".gitconfig".text = ''
      # Managed by Home Manager. Git config lives in ${config.xdg.configHome}/git/config.
    '';
    ".ssh/git_signing_key.pub".text = "${signingPublicKey}\n";
    ".ssh/allowed_signers".text = "${signingEmail} ${signingPublicKey}\n";
  };
}
