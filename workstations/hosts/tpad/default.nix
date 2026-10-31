# ThinkPad (Pop!_OS) host configuration for home-manager standalone
{ pkgs, inputs, ... }:
let
  t3code = import ../../../modules/t3code.nix {
    inherit pkgs inputs;
    # T3 runs both providers through Hestia's CLIProxyAPI.
    codex = import ../../../modules/codex-proxy.nix {
      inherit pkgs;
      codex = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
    claude = import ../../../modules/claude-proxy.nix {
      inherit pkgs;
      claude = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      name = "claude";
    };
  };
  tailscale-headscale-setup = pkgs.writeShellApplication {
    name = "tailscale-headscale-setup";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./tailscale-headscale-setup.sh;
  };
  lights-toggle = pkgs.writeShellApplication {
    name = "lights-toggle";
    runtimeInputs = [
      pkgs.glib
      pkgs.xrandr
    ];
    text = builtins.readFile ./lights-toggle.sh;
  };
in
{
  # This is a minimal configuration for running home-manager standalone on Pop!_OS
  # We're not managing the system itself, just the user environment

  # Allow unfree packages (needed for Discord, Steam, etc.)
  nixpkgs.config.allowUnfree = true;

  # Integrate this non-NixOS host with Home Manager, including native GPU
  # drivers exposed through /run/opengl-driver.
  targets.genericLinux.enable = true;

  # Pop!_OS owns the privileged tailscaled service. Keep using its matching
  # system CLI and expose an idempotent command for applying our client prefs.
  home.packages = [
    tailscale-headscale-setup
    lights-toggle
    t3code.desktop
  ]
  ++ t3code.direnvProviders;

  home.file.".codex/hestia.config.toml".text = ''
    model_provider = "hestia"

    [model_providers.hestia]
    name = "Hestia CLIProxyAPI"
    base_url = "https://hestia.vpn.miksu.app:8317/v1"
    wire_api = "responses"
    requires_openai_auth = false
  '';
  programs.zsh.shellAliases.codex-hestia = "codex";

  # The nixpkgs Ghostty GApps wrapper exports GIO_EXTRA_MODULES (Nix dconf) and
  # its shells inherit it, so Pop's glib programs (flatpak, fwupdmgr) fail to
  # load the module. Ghostty's `env` option cannot unset inherited variables.
  programs.zsh.envExtra = ''
    if [[ -n $GHOSTTY_RESOURCES_DIR && $SHLVL -eq 1 ]]; then
      unset GIO_EXTRA_MODULES
    fi
  '';
}
