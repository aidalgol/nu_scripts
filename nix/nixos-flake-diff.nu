#!/usr/bin/env nu

let worktree_base_dir = '.worktree'

def commitish_worktree_dir [
  commitish: string
] {
  [$worktree_base_dir, $commitish] | path join
}

def cleanup_worktrees [
  commitishes: list
] {
  $commitishes | each {|commitish|
    let result = (do {
      git worktree remove --force (commitish_worktree_dir $commitish)
    } | complete)
    if $result.exit_code != 0 {
      print --no-newline $result.stderr
      print --stderr "An error occurred removing the git worktrees.  You may need to clean up manually."
      exit 1
    }
  }
  rm $worktree_base_dir
}

# Determine whether two commits of a NixOS configuration (Git repository) are
# equivalent.
def main [
  commitish_A: string = 'HEAD' # First commitish object. Defaults to HEAD
  commitish_B: string = 'HEAD~' # Second commitish object. Defaults to HEAD~
  --hostname: string # Hostname to pass to nixos-rebuild
] {
  let commitishes = [$commitish_A, $commitish_B]
  $commitishes | each {|commitish|
    let result = (do { 
      git worktree add --quiet --detach (commitish_worktree_dir $commitish) $commitish
    } | complete)
    if $result.exit_code != 0 {
      print --no-newline $result.stderr
      print --stderr "An error occurred trying to create git worktrees.  Unable to continue."
      exit 1
    }
  }
  try {
    $commitishes | each {|commitish|
      do {
        cd (commitish_worktree_dir $commitish)
        print $"Building ($commitish)"
        let result = (do { nixos-rebuild --flake $".#($hostname)" build } | complete)
        if $result.exit_code != 0 {
          print --no-newline $result.stderr
          print --stderr "nixos-rebuild failed"
          cleanup_worktrees $commitishes
          exit 1
        }
      }
    }
    let store_paths = ($commitishes | each {|commitish|
      ([(commitish_worktree_dir $commitish), result] | path join) | path expand
    })
    if $store_paths.0 != $store_paths.1 {
      print "Build results are different"
      $store_paths | to text
      cleanup_worktrees $commitishes
      exit 1
    } else {
      print "Build results are the same"
      cleanup_worktrees $commitishes
    }
  } catch {
    # In the event of an error, clean up the git worktrees we created.
    cleanup_worktrees $commitishes
    exit 1
  }
}
