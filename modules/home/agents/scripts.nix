# Custom scripts
{ pkgs, ... }:
let
  claude-worktree = pkgs.writeShellScriptBin "claude-worktree" (
    builtins.readFile ./scripts/claude-worktree.sh
  );
in
{
  home.packages = [
    claude-worktree
  ];
}
