# Zsh configuration - platform-agnostic
{
  lib,
  isDarwin ? false,
  ...
}:
{
  home = {
    sessionVariables.PNPM_HOME = "$HOME/.local/share/pnpm";

    sessionPath = [
      "$HOME/.local/share/pnpm"
      "$HOME/.bun/bin"
      "$HOME/.local/bin"
    ];

    activation.createPnpmHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.local/share/pnpm"
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = false; # we handle compinit manually for speed
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      # Custom
      p = "pnpm";
      tf = if isDarwin then "tofu" else "terraform";
      bb = "bun --bun";
      treefmt = "treefmt --config-file ~/.config/treefmt/treefmt.toml --allow-missing-formatter";
      tp = "trash-put";

      # Git (from oh-my-zsh git plugin)
      g = "git";
      ga = "git add";
      gaa = "git add --all";
      gapa = "git add --patch";
      gau = "git add --update";
      gav = "git add --verbose";
      gam = "git am";
      gama = "git am --abort";
      gamc = "git am --continue";
      gamscp = "git am --show-current-patch";
      gams = "git am --skip";
      gap = "git apply";
      gapt = "git apply --3way";
      gbs = "git bisect";
      gbsb = "git bisect bad";
      gbsg = "git bisect good";
      gbsn = "git bisect new";
      gbso = "git bisect old";
      gbsr = "git bisect reset";
      gbss = "git bisect start";
      gbl = "git blame -w";
      gb = "git branch";
      gba = "git branch --all";
      gbd = "git branch --delete";
      gbD = "git branch --delete --force";
      gbgd = ''LANG=C git branch --no-color -vv | grep ": gone\]" | cut -c 3- | awk '{print $1}' | xargs git branch -d'';
      gbgD = ''LANG=C git branch --no-color -vv | grep ": gone\]" | cut -c 3- | awk '{print $1}' | xargs git branch -D'';
      gbm = "git branch --move";
      gbnm = "git branch --no-merged";
      gbr = "git branch --remote";
      ggsup = "git branch --set-upstream-to=origin/$(git_current_branch)";
      gbg = ''LANG=C git branch -vv | grep ": gone\]"'';
      gco = "git checkout";
      gcor = "git checkout --recurse-submodules";
      gcb = "git checkout -b";
      gcB = "git checkout -B";
      gcd = "git checkout $(git_develop_branch)";
      gcm = "git checkout $(git_main_branch)";
      gcp = "git cherry-pick";
      gcpa = "git cherry-pick --abort";
      gcpc = "git cherry-pick --continue";
      gclean = "git clean --interactive -d";
      gcl = "git clone --recurse-submodules";
      gclf = "git clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules";
      gcam = "git commit --all --message";
      gcas = "git commit --all --signoff";
      gcasm = "git commit --all --signoff --message";
      gcs = "git commit --gpg-sign";
      gcss = "git commit --gpg-sign --signoff";
      gcssm = "git commit --gpg-sign --signoff --message";
      gcmsg = "git commit --message";
      gcsm = "git commit --signoff --message";
      gc = "git commit --verbose";
      gca = "git commit --verbose --all";
      "gca!" = "git commit --verbose --all --amend";
      "gcan!" = "git commit --verbose --all --no-edit --amend";
      "gcans!" = "git commit --verbose --all --signoff --no-edit --amend";
      "gcann!" = "git commit --verbose --all --date=now --no-edit --amend";
      "gc!" = "git commit --verbose --amend";
      gcn = "git commit --verbose --no-edit";
      "gcn!" = "git commit --verbose --no-edit --amend";
      gcf = "git config --list";
      gcfu = "git commit --fixup";
      gdct = "git describe --tags $(git rev-list --tags --max-count=1)";
      gd = "git diff";
      gdca = "git diff --cached";
      gdcw = "git diff --cached --word-diff";
      gds = "git diff --staged";
      gdw = "git diff --word-diff";
      gdup = "git diff @{upstream}";
      gdt = "git diff-tree --no-commit-id --name-only -r";
      gf = "git fetch";
      gfa = "git fetch --all --tags --prune --jobs=10";
      gfo = "git fetch origin";
      gg = "git gui citool";
      gga = "git gui citool --amend";
      ghh = "git help";
      glgg = "git log --graph";
      glgga = "git log --graph --decorate --all";
      glgm = "git log --graph --max-count=10";
      glods = ''git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset" --date=short'';
      glod = ''git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset"'';
      glola = ''git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --all'';
      glols = ''git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset" --stat'';
      glol = ''git log --graph --pretty="%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset"'';
      glo = "git log --oneline --decorate";
      glog = "git log --oneline --decorate --graph";
      gloga = "git log --oneline --decorate --graph --all";
      glg = "git log --stat";
      glgp = "git log --stat --patch";
      gignored = ''git ls-files -v | grep "^[[:lower:]]"'';
      gfg = "git ls-files | grep";
      gm = "git merge";
      gma = "git merge --abort";
      gmc = "git merge --continue";
      gms = "git merge --squash";
      gmff = "git merge --ff-only";
      gmom = "git merge origin/$(git_main_branch)";
      gmum = "git merge upstream/$(git_main_branch)";
      gmtl = "git mergetool --no-prompt";
      gmtlvim = "git mergetool --no-prompt --tool=vimdiff";
      gl = "git pull";
      gpr = "git pull --rebase";
      gprv = "git pull --rebase -v";
      gpra = "git pull --rebase --autostash";
      gprav = "git pull --rebase --autostash -v";
      gprom = "git pull --rebase origin $(git_main_branch)";
      gpromi = "git pull --rebase=interactive origin $(git_main_branch)";
      gprum = "git pull --rebase upstream $(git_main_branch)";
      gprumi = "git pull --rebase=interactive upstream $(git_main_branch)";
      ggpull = ''git pull origin "$(git_current_branch)"'';
      gluc = "git pull upstream $(git_current_branch)";
      glum = "git pull upstream $(git_main_branch)";
      gp = "git push";
      gpd = "git push --dry-run";
      "gpf!" = "git push --force";
      gpf = "git push --force-with-lease --force-if-includes";
      gpsup = "git push --set-upstream origin $(git_current_branch)";
      gpsupf = "git push --set-upstream origin $(git_current_branch) --force-with-lease --force-if-includes";
      gpv = "git push --verbose";
      gpoat = "git push origin --all && git push origin --tags";
      gpod = "git push origin --delete";
      ggpush = ''git push origin "$(git_current_branch)"'';
      gpu = "git push upstream";
      grb = "git rebase";
      grba = "git rebase --abort";
      grbc = "git rebase --continue";
      grbi = "git rebase --interactive";
      grbo = "git rebase --onto";
      grbs = "git rebase --skip";
      grbd = "git rebase $(git_develop_branch)";
      grbm = "git rebase $(git_main_branch)";
      grbom = "git rebase origin/$(git_main_branch)";
      grbum = "git rebase upstream/$(git_main_branch)";
      grf = "git reflog";
      gr = "git remote";
      grv = "git remote --verbose";
      gra = "git remote add";
      grrm = "git remote remove";
      grmv = "git remote rename";
      grset = "git remote set-url";
      grup = "git remote update";
      grh = "git reset";
      gru = "git reset --";
      grhh = "git reset --hard";
      grhk = "git reset --keep";
      grhs = "git reset --soft";
      gpristine = "git reset --hard && git clean --force -dfx";
      gwipe = "git reset --hard && git clean --force -df";
      groh = "git reset origin/$(git_current_branch) --hard";
      grs = "git restore";
      grss = "git restore --source";
      grst = "git restore --staged";
      gunwip = ''git rev-list --max-count=1 --format="%s" HEAD | grep -q "\--wip--" && git reset HEAD~1'';
      grev = "git revert";
      greva = "git revert --abort";
      grevc = "git revert --continue";
      grm = "git rm";
      grmc = "git rm --cached";
      gcount = "git shortlog --summary --numbered";
      gsh = "git show";
      gsps = "git show --pretty=short --show-signature";
      gstall = "git stash --all";
      gstaa = "git stash apply";
      gstc = "git stash clear";
      gstd = "git stash drop";
      gstl = "git stash list";
      gstp = "git stash pop";
      gsta = "git stash push";
      gstu = "gsta --include-untracked";
      gsts = "git stash show --patch";
      gst = "git status";
      gss = "git status --short";
      gsb = "git status --short --branch";
      gsi = "git submodule init";
      gsu = "git submodule update";
      gsd = "git svn dcommit";
      gsr = "git svn rebase";
      gsw = "git switch";
      gswc = "git switch --create";
      gswd = "git switch $(git_develop_branch)";
      gswm = "git switch $(git_main_branch)";
      gta = "git tag --annotate";
      gts = "git tag --sign";
      gtv = "git tag | sort -V";
      gignore = "git update-index --assume-unchanged";
      gunignore = "git update-index --no-assume-unchanged";
      gwch = "git log --patch --abbrev-commit --pretty=medium --raw";
      gwt = "git worktree";
      gwta = "git worktree add";
      gwtls = "git worktree list";
      gwtmv = "git worktree move";
      gwtrm = "git worktree remove";
      gwip = ''git add -A; git rm $(git ls-files --deleted) 2> /dev/null; git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"'';
      grt = ''cd "$(git rev-parse --show-toplevel || echo .)"'';
    };

    initContent = lib.mkMerge (
      # Darwin-specific nix-daemon setup
      (lib.optionals isDarwin [
        (lib.mkBefore ''
          if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
            . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
            . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
          fi
        '')
      ])
      ++ [
        ''
          # Completion system (cached only — no full rescan on every shell)
          autoload -Uz compinit
          compinit -C

          # Completion styles (from oh-my-zsh lib/completion.zsh)
          zmodload -i zsh/complist
          WORDCHARS=""
          unsetopt menu_complete
          unsetopt flowcontrol
          setopt auto_menu
          setopt complete_in_word
          setopt always_to_end
          zstyle ':completion:*:*:*:*:*' menu select
          zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|=*' 'l:|=* r:|=*'
          zstyle ':completion:*' special-dirs true
          zstyle ':completion:*' list-colors ""
          zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
          zstyle ':completion:*:*:*:*:processes' command "ps -u $USERNAME -o pid,user,comm -w -w"
          zstyle ':completion:*:cd:*' tag-order local-directories directory-stack path-directories
          zstyle ':completion:*' use-cache yes
          zstyle ':completion:*' cache-path "$HOME/.cache/zsh/compcache"
          autoload -U +X bashcompinit && bashcompinit

          # Key bindings (emacs mode)
          bindkey -e
          if (( ''${+terminfo[smkx]} )) && (( ''${+terminfo[rmkx]} )); then
            function zle-line-init() { echoti smkx }
            function zle-line-finish() { echoti rmkx }
            zle -N zle-line-init
            zle -N zle-line-finish
          fi

          # ~/systems shortcuts: `cd workstations` or `cd infra` from anywhere, and ~sys
          cdpath=(~/systems $cdpath)
          hash -d sys=~/systems

          # Misc settings (from oh-my-zsh lib/misc.zsh)
          setopt multios
          setopt long_list_jobs
          setopt interactivecomments
          for d in $fpath; do
            if [[ -e "$d/url-quote-magic" ]]; then
              autoload -Uz bracketed-paste-magic url-quote-magic
              zle -N bracketed-paste bracketed-paste-magic
              zle -N self-insert url-quote-magic
              break
            fi
          done

          # Git helper functions (used by aliases)
          function git_current_branch() {
            local ref
            ref=$(command git symbolic-ref --quiet HEAD 2>/dev/null)
            local ret=$?
            if [[ $ret != 0 ]]; then
              [[ $ret == 128 ]] && return
              ref=$(command git rev-parse --short HEAD 2>/dev/null) || return
            fi
            echo ''${ref#refs/heads/}
          }

          function git_main_branch() {
            command git rev-parse --git-dir &>/dev/null || return
            local ref
            for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
              if command git show-ref -q --verify $ref; then
                echo ''${ref:t}
                return 0
              fi
            done
            for remote in origin upstream; do
              ref=$(command git rev-parse --abbrev-ref $remote/HEAD 2>/dev/null)
              if [[ $ref == $remote/* ]]; then
                echo ''${ref#"$remote/"}
                return 0
              fi
            done
            echo master
            return 1
          }

          function git_develop_branch() {
            command git rev-parse --git-dir &>/dev/null || return
            local branch
            for branch in dev devel develop development; do
              if command git show-ref -q --verify refs/heads/$branch; then
                echo $branch
                return 0
              fi
            done
            echo develop
            return 1
          }

          function grename() {
            if [[ -z "$1" || -z "$2" ]]; then
              echo "Usage: $0 old_branch new_branch"
              return 1
            fi
            git branch -m "$1" "$2"
            if git push origin :"$1"; then
              git push --set-upstream origin "$2"
            fi
          }

          function gbda() {
            git branch --no-color --merged | command grep -vE "^([+*]|\s*($(git_main_branch)|$(git_develop_branch))\s*$)" | command xargs git branch --delete 2>/dev/null
          }

          function gbds() {
            local default_branch=$(git_main_branch)
            (( ! $? )) || default_branch=$(git_develop_branch)
            git for-each-ref refs/heads/ "--format=%(refname:short)" | \
              while read branch; do
                local merge_base=$(git merge-base $default_branch $branch)
                if [[ $(git cherry $default_branch $(git commit-tree $(git rev-parse $branch\^{tree}) -p $merge_base -m _)) = -* ]]; then
                  git branch -D $branch
                fi
              done
          }

          function gunwipall() {
            local _commit=$(git log --grep='--wip--' --invert-grep --max-count=1 --format=format:%H)
            if [[ "$_commit" != "$(git rev-parse HEAD)" ]]; then
              git reset $_commit || return 1
            fi
          }

          function work_in_progress() {
            command git -c log.showSignature=false log -n 1 2>/dev/null | grep -q -- "--wip--" && echo "WIP!!"
          }

          function gdv() { git diff -w "$@" | view - }

          function gdnolock() {
            git diff "$@" ":(exclude)package-lock.json" ":(exclude)*.lock"
          }

          function _git_log_prettily() {
            if ! [ -z $1 ]; then
              git log --pretty=$1
            fi
          }
          alias glp='_git_log_prettily'
          alias gtl='gtl(){ git tag --sort=-v:refname -n --list "''${1}*" }; noglob gtl'

          # GPG TTY for signing
          export GPG_TTY=$(tty)

          # Hide user@host when local (used by some prompts)
          export DEFAULT_USER=$(whoami)

          # fnm (Fast Node Manager) integration
          if (( $+commands[fnm] )); then
            eval "$(fnm env --use-on-cd --shell zsh)"
          fi
        ''
      ]
      # Darwin lacks systemd-user cgroups, so cmux pty close leaves orphaned
      # dev-server children. Trap EXIT to SIGTERM our pgroup. Daemons
      # (docker -d, brew services) live in their own pgroup, safe.
      ++ (lib.optionals isDarwin [
        ''
          if [[ -o interactive && $SHLVL -eq 1 ]]; then
            trap 'kill -TERM -- -$$ 2>/dev/null' EXIT
          fi
        ''
      ])
    );
  };
}
