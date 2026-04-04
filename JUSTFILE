default:
  just --list

[group('helpers')]
update:
  git submodule update --recursive

[group('helpers')]
foreach *args:
  git -c protocol.file.allow=always submodule foreach {{args}}

[group('helpers')]
update-just:
  git submodule foreach 'cd .just; git checkout main; git pull'
  git submodule foreach 'git add .just; git commit -m "chore: Update just submodule"; git push'

mod berlin
mod? dubai
mod dunkirk
mod london
mod newyork
mod paris
mod washington

# Update all homelab hosts with the new homelab flake
[group('homelab')]
update-homelab:
  just update-homelab-flakes homelab nix-config

update-homelab-flakes *flakes="":
  just _pre-homelab-update-check
  just _update-homelab-hosts {{flakes}}

_pre-homelab-update-check:
  just foreach 'just check-clean'

_update-homelab-hosts *flakes="":
  just update-homelab-service-hosts {{flakes}}
  just update-homelab-networking {{flakes}}
  just update-homelab-clients {{flakes}}
  echo "Finished updating all homelab hosts"

# Update all homelab hosts that host services
[group('homelab')]
update-homelab-service-hosts *flakes="":
  just washington::deploy-update {{flakes}}
  # NOTE: Currently offline due to dead server
  # just london::deploy-new-homelab
  echo "Finished updating homelab service hosts"

# Update all homelab hosts that control networking
[group('homelab')]
update-homelab-networking *flakes="": 
  just newyork::deploy-update {{flakes}}
  echo "Finished updating homelab network hosts"

# Update all hosts that need to connect to homelab hosts
[group('homelab'), parallel]
update-homelab-clients *flakes="": 
  -just berlin::deploy-update {{flakes}}
  -just paris::deploy-update {{flakes}}
  echo "Finished updating homelab clients"
