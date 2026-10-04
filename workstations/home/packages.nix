# Workstation development toolchain. Shared shell tools live in
# modules/home/core, coding agents in modules/home/agents.
{
  pkgs,
  lib,
  isDarwin ? false,
  ...
}:
{
  home = {
    # Global treefmt config — used as fallback when no repo-local treefmt.toml exists
    file.".config/treefmt/treefmt.toml".source = ./treefmt.toml;

    packages =
      with pkgs;
      [
        # Languages & runtimes
        python3
        fnm
        bun
        rustup

        # Package managers & tools
        uv

        # Nix tooling
        nixfmt-tree

        # Formatting
        oxfmt

        # Databases
        postgresql_18
        redis
        sqlite

        # Cloud
        (azure-cli.withExtensions [
          (azure-cli.extensions.containerapp.overridePythonAttrs {
            pythonRelaxDeps = [ "kubernetes" ];
          })
        ])

        # Media
        ffmpeg
        imagemagick

        # Document processing
        # Convert Markdown to PDF: pandoc input.md -o output.pdf --pdf-engine=typst
        pandoc
        typst
        poppler-utils
        typstyle

        # Development tools
        shellcheck
        shfmt
        mergiraf

        # Security
        _1password-cli
      ]
      # Platform-specific packages (NixOS/Linux only - macOS uses Homebrew)
      ++ lib.optionals (!isDarwin) [
        terraform
      ]
      # Platform-specific packages (macOS only)
      ++ lib.optionals isDarwin [
        opentofu
        google-cloud-sdk
      ];
  };
}
