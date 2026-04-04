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

mod berlin
mod dubai
mod dunkirk
mod london
mod newyork
mod paris
mod washington

# Update all homelab hosts with the new homelab flake
[group('homelab')]
update-homelab:
  nix flake check git+ssh://git@github.com/GrimOutlook/nix-homelab
  just _update-homelab-hosts

[hidden]
_update-homelab-hosts: \
    update-homelab-service-hosts \
    update-homelab-network \
    update-homelab-clients
  echo "Finished updating all homelab hosts"

# Update all homelab hosts that host services
[group('homelab'), parallel]
update-homelab-service-hosts: (washingon::deploy) (london::deploy)
  echo "Finished updating homelab service hosts"

# Update all homelab hosts that control networking
[group('homelab')]
update-homelab-networking: (newyork::deploy)
  echo "Finished updating homelab network hosts"

# Update all hosts that need to connect to homelab hosts
[group('homelab'), parallel]
update-homelab-clients: (berlin::deploy) (paris::deploy)
  echo "Finished updating homelab clients"
