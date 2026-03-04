default:
  just --list

update:
  git submodule update --recursive

foreach *args:
  git -c protocol.file.allow=always submodule foreach {{args}}

flake-update:
  just foreach 'nix flake update'
  just foreach 'nix flake check'
  just foreach "'git commit -am \"chore: Update flake.lock\" && git push || true'"
  git commit -am "chore: Update all submodule flake.lock" && git push
  just push-all

push-all:
  just foreach "git send"
  git send
