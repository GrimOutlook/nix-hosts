default:
  just --list

update:
  git submodule update --recursive

foreach *args:
  git submodule foreach {{args}}

flake-update:
  just foreach 'nix flake update'
  just foreach 'nix flake check'
  just foreach 'git commit -am "chore: Update flake.lock"'
  git commit -am "chore: Update all submodule flake.lock"
