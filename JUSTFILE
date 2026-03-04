default:
  just --list

update:
  git submodule update --recursive

foreach *args:
  git -c protocol.file.allow=always submodule foreach {{args}}

flake-update:
  just foreach 'nix flake update'
  just foreach 'nix flake check'
  just foreach 'git diff --quiet || git diff --cached --quiet && git commit -am "chore: Update flake.lock"'
  git diff --quiet || git diff --cached --quiet && git commit -am "chore: Update all submodule flake.lock"
