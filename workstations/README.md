# Nix Configuration

[![Workstations](https://github.com/MikaelSiidorow/systems/actions/workflows/workstations.yml/badge.svg)](https://github.com/MikaelSiidorow/systems/actions/workflows/workstations.yml)

Nix configuration for macOS (nix-darwin) and Linux (home-manager standalone).

Configured hosts:

| Host   | Attr                            | Platform       | Notes                                 |
| ------ | ------------------------------- | -------------- | ------------------------------------- |
| `mbp`  | `Mikael-MacBook-Pro-H7D6Q4TMVY` | aarch64-darwin | nix-darwin; attr is the LocalHostName |
| `tpad` | `mikaelsiidorow@tpad`           | x86_64-linux   | home-manager standalone on Pop!\_OS   |

Hestia's NixOS configuration and the OpenWrt router configurations live in
[`infra/`](../infra/) in this repository.

## Quick Start

### macOS (fresh machine)

The flake assumes Determinate Nix (`nix.enable = false`), so the upstream installer will not work.

```bash
# 1. Install Determinate Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2. Install Rosetta. Colima uses it to run amd64 containers on Apple silicon.
softwareupdate --install-rosetta --agree-to-license

# 3. Set LocalHostName to match a darwinConfigurations attr.
#    darwin-rebuild reads scutil --get LocalHostName as the default target.
sudo scutil --set HostName Mikael-MacBook-Pro-H7D6Q4TMVY
sudo scutil --set LocalHostName Mikael-MacBook-Pro-H7D6Q4TMVY
sudo scutil --set ComputerName Mikael-MacBook-Pro-H7D6Q4TMVY

# 4. Clone.
git clone https://github.com/MikaelSiidorow/systems.git ~/systems
cd ~/systems/workstations

# 5. Bootstrap nix-darwin using the locked flake input. After this, `make switch` is available.
#    Succeeds without secrets; sops-nix decryption fails quietly until the age key exists.
nix run .#darwin-rebuild -- switch --flake .

# 6. Restore the SOPS age key (see "SOPS age key restore" below), then `make switch` again to decrypt.
```

If you need a different hostname, add it to `darwinHosts` (top of `flake.nix`) before switching.

Optional: append `extra-substituters = https://cache.flakehub.com` to `/etc/nix/nix.custom.conf` if you want the FlakeHub cache actually queried (Determinate marks it trusted but doesn't query it). Leave the `access-tokens` line alone.

### SOPS age key restore

The age private key at `~/.config/sops/age/keys.txt` unlocks the repo's encrypted secrets. It is intentionally not managed by Nix; it is the recovery key, backed up in Bitwarden as `sops age key`. rbw, pinentry, and rbw's config (email, base_url, pinentry) are all managed declaratively by `home/sops.nix`, so there is nothing to `rbw config set` by hand.

`rbw register` asks for a Bitwarden personal API key: paste the `client_id`, then `client_secret`, from the web vault under **Settings > Security > Keys > "View API Key"**. That authorizes this CLI device past Bitwarden's new-client login challenge; you still enter the master password at `rbw login`.

**macOS:** the first `make switch` succeeds without the key (sops-nix decryption runs as a launchd agent and just logs a failure to `~/Library/Logs/SopsNix/`). So switch first, then restore the key with the now-installed rbw:

```bash
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops ~/.config/sops/age

rbw register   # client_id, then client_secret (see above)
rbw login      # master password

( umask 077
  rbw get "sops age key" \
    | awk '/^AGE-SECRET-KEY-/ { print; found=1 } END { if (!found) exit 1 }' \
    > ~/.config/sops/age/keys.txt
)

make switch    # re-runs decryption; the git signing key and other secrets land now

age-keygen -y ~/.config/sops/age/keys.txt   # optional: prints only the public age recipient
```

**Linux:** decryption runs as a blocking systemd user service during activation, so restore the key before the first activation. rbw is not installed yet, so run it from a temporary shell (pinentry-curses provides the `pinentry` binary rbw prompts through):

```bash
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops ~/.config/sops/age

nix shell nixpkgs#rbw nixpkgs#pinentry-curses -c sh -c '
  rbw config set base_url "https://api.bitwarden.eu"
  rbw config set identity_url "https://identity.bitwarden.eu"
  rbw config set ui_url "https://vault.bitwarden.eu"
  rbw config set notifications_url "https://notifications.bitwarden.eu"
  rbw config set email "<bitwarden-account-email>"
  rbw register
  rbw login
  umask 077
  rbw get "sops age key" \
    | awk "/^AGE-SECRET-KEY-/ { print; found=1 } END { if (!found) exit 1 }" \
    > ~/.config/sops/age/keys.txt
'
```

Whenever rbw is locked or stale later: `rbw unlock`, `rbw sync`.

### Linux (Pop!\_OS)

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
# Lets the user-level nix.conf enable the numtide cache without trusted-users.
sudo tee -a /etc/nix/nix.custom.conf <<'EOF'
extra-trusted-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
EOF
sudo systemctl restart nix-daemon

git clone https://github.com/MikaelSiidorow/systems.git ~/systems
cd ~/systems/workstations

# Restore the SOPS age key using the commands above before activating.
```

Activate Home Manager:

```bash
# Bootstrap using the locked home-manager input.
nix run .#home-manager -- switch --flake .#mikaelsiidorow@tpad -b backup

# Subsequent updates
make switch
```

Pop!\_OS owns the privileged `tailscaled` system service rather than Home
Manager. After installing and enabling Tailscale through the host OS, apply the
repeatable Headscale client preferences with:

```bash
tailscale-headscale-setup
```

The command connects to `https://hs.miksu.app`, accepts Headscale DNS, and
accepts the home LAN subnet route. It is safe to run again.

## Common Commands

```bash
make switch       # Build and activate
make diff         # Preview changes
make update       # Update inputs
make update-fast  # Update fast-moving app inputs
make upgrade      # Update + switch
make brew-upgrade # Explicit Homebrew update + upgrade on macOS
make check        # Validate flake
make fmt          # Format code
```

On macOS `make switch` passes `--flake .` and lets `darwin-rebuild` resolve to `darwinConfigurations.$(scutil --get LocalHostName)`. Run `make help` for the full list.

Homebrew packages are not upgraded during `make switch`; run `make brew-upgrade` when you want casks and brews updated.

## Source policy

The default package set is `nixpkgs` on `nixos-26.05`. Fast-moving user apps can use `nixpkgs-unstable` explicitly; Firefox and Vesktop are wired this way so app updates can move ahead of the default package set.

Use `make update-fast` to update app/catalog inputs without moving the default stable package set: `nixpkgs-unstable`, NUR, nix-index database, Claude Code, Codex, OpenCode, and Homebrew (`nix-homebrew` plus taps; brew and cask DSL must stay in sync). Use `make update` when you want all flake inputs updated together.

`bitwarden-desktop` is not currently installed from Nix because `nixos-26.05` packages it with Electron 39, which nixpkgs marks EOL/insecure. The Firefox Bitwarden extension remains managed by Nix.

## Secrets

Secrets use `sops-nix` with a single personal age recipient. The age private key lives at `~/.config/sops/age/keys.txt` on each machine and is backed up in Bitwarden as `sops age key`.

Current managed secret:

- `ssh/git_signing_key` -> `~/.ssh/git_signing_key`, used for SSH commit and tag signing.
- `hf/token` -> the Home Manager sops secret directory, kept for Hugging Face access.

Git signing is declarative in `home/git.nix` and uses `mikael@siidorow.com`. The public key is written to `~/.ssh/git_signing_key.pub`; add it to GitHub as an SSH **Signing key** if it is not already present:

```bash
gh ssh-key add ~/.ssh/git_signing_key.pub --type signing --title "Pop!_OS git signing"
```

The GitHub signing key is account-level, so a new machine that decrypts the same signing key does not need a second GitHub registration.

### Trial Claude Code through Hestia

On Hestia, log in once:

```bash
sudo -u cli-proxy-api cli-proxy-api \
  -config /var/lib/cli-proxy-api/config.yaml -claude-login -no-browser
```

Open the printed URL. If the localhost redirect fails on the ThinkPad, paste
the full callback URL into the Hestia terminal when prompted. Keep it private.

After `make switch` on the ThinkPad, run `claude-hestia`. Plain `claude` keeps
your existing setup. Smoke test:

```bash
claude-hestia --model claude-sonnet-5 -p --tools '' 'Reply with exactly: proxy-ok'
```

claude.ai connectors are disabled. Refresh over days remains untested;
subscription proxy support is unresolved under
[Anthropic's guidance](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use).

## Migration checklist

Not managed by the flake (bring over manually):

- SSH authentication keys for GitHub pushes. The SSH signing key is managed by sops-nix.
- App logins: Slack, Teams, browser, `gh auth login`
- Browser data via sign-in (Firefox Sync, Chrome sync); extensions are nix-managed
- VS Code settings via account sync; the binary is nix-managed
- Mutable `~/.claude/` state: `settings.json`, memories, history, plugins. `CLAUDE.md` and `statusline-command.sh` are home-managed.

## Structure

```
├── flake.nix              # Hosts, overlays, system constructors
├── Makefile               # Build commands (OS-detected)
├── hosts/{mbp,tpad}/      # Per-host modules
├── modules/darwin/
├── home/                  # Workstation home-manager: desktop apps, git, sops, dev toolchain
├── pkgs/                  # Custom packages and wrappers
└── profiles/apple/        # Configuration profiles, installed by opening them on the device
```

Shared home-manager modules live outside this flake, in `../modules/home/`:
`core/` (shell and everyday CLI tools) and `agents/` (coding agent CLIs,
skills and config). Both are imported by `home/default.nix`.

## Troubleshooting

**Nix daemon not found:**

```bash
. '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
```

**GPU setup on non-NixOS Linux:** Home Manager exposes the Nixpkgs graphics
drivers through `/run/opengl-driver`. After a driver update, run the
`non-nixos-gpu-setup` command printed by `home-manager switch`.

## License

MIT
