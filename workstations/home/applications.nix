# Desktop applications - platform-agnostic
{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  vscodeExtensions = with pkgs-unstable.vscode-extensions; [
    astro-build.astro-vscode
    bradlc.vscode-tailwindcss
    charliermarsh.ruff
    dbaeumer.vscode-eslint
    docker.docker
    eamodio.gitlens
    esbenp.prettier-vscode
    github.vscode-github-actions
    github.vscode-pull-request-github
    hashicorp.terraform
    jnoortheen.nix-ide
    mechatroner.rainbow-csv
    mikestead.dotenv
    ms-azuretools.vscode-containers
    ms-kubernetes-tools.vscode-kubernetes-tools
    ms-python.debugpy
    ms-python.python
    ms-python.vscode-python-envs
    ms-toolsai.jupyter
    ms-toolsai.jupyter-keymap
    ms-toolsai.jupyter-renderers
    ms-toolsai.vscode-jupyter-cell-tags
    ms-vscode.makefile-tools
    myriad-dreamin.tinymist
    # Unstable currently builds oxlint locally and its N-API packaging step is
    # blocked by the Darwin sandbox. Stable is available from cache.
    pkgs.vscode-extensions.oxc.oxc-vscode
    pkief.material-icon-theme
    redhat.vscode-yaml
    rust-lang.rust-analyzer
    stylelint.vscode-stylelint
    svelte.svelte-vscode
    tamasfe.even-better-toml
    timonwong.shellcheck
    usernamehw.errorlens
    yoavbls.pretty-ts-errors
  ];
in
{
  programs = {
    # Ghostty: Not in nixpkgs for macOS yet
    # macOS: install via Homebrew (see modules/darwin/homebrew.nix)
    # Linux: install from nixpkgs (see home/applications-linux.nix)

    vscode = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
      package = pkgs-unstable.vscode;
      mutableExtensionsDir = false;
      profiles.default.extensions = vscodeExtensions;
    };

  };
}
