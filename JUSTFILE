FLAKE_STUB := "git+ssh://git@github.com/GrimOutlook/nix-host-"

default:
  just --list

update:
  git submodule update --recursive
