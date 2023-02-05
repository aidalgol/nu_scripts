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
    git worktree remove --force (commitish_worktree_dir $commitish)
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
    git worktree add --quiet --detach (commitish_worktree_dir $commitish) $commitish
  }
  try {
    $commitishes | each {|commitish|
      do {
        cd (commitish_worktree_dir $commitish)
        print $commitish
        nixos-rebuild --flake $".#($hostname)" build
      }
    }
    let store_paths = ($commitishes | each {|commitish|
      ([(commitish_worktree_dir $commitish), result] | path join) | path expand
    })
    mut result_code = 0
    if $store_paths.0 != $store_paths.1 {
      print "Build results are different"
      $store_paths | to text
      result_code = 1
    } else {
      print "Build results are the same"
    }
    # Clean up now that we're done.
    cleanup_worktrees $commitishes
    exit $result_code
  } catch {
    # In the event of an error, clean up the git worktrees we created.
    cleanup_worktrees $commitishes
    exit 1
  }
}
