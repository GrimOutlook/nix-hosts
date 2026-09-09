{
  description = "Fleet aggregator: deploy-rs nodes for every nix-host repo";

  inputs = {
    deploy-rs.url = "github:serokell/deploy-rs";

    # nixpkgs only provides `lib` here -- nothing in this flake is built
    # against it. Follow one host so the aggregator adds no extra nixpkgs.
    nixpkgs.follows = "berlin/nixpkgs";

    # Each host stays in its own repo, pinned independently, exactly as
    # today. Public repos over https, private ones over ssh.
    amsterdam.url = "git+ssh://git@github.com/GrimOutlook/nix-host-amsterdam";
    berlin.url = "github:GrimOutlook/nix-host-berlin";
    dubai.url = "github:GrimOutlook/nix-host-dubai";
    macao.url = "github:GrimOutlook/nix-host-macao";
    newyork.url = "git+ssh://git@github.com/GrimOutlook/nix-host-newyork";
    oslo.url = "github:GrimOutlook/nix-host-oslo";
    paris.url = "github:GrimOutlook/nix-host-paris";
    # The repo was renamed to nix-host-dunkirk; the host is still pyongyang,
    # so the input keeps the host's name and points at the new repo. Private,
    # hence ssh.
    pyongyang.url = "git+ssh://git@github.com/GrimOutlook/nix-host-dunkirk";
    svalbard.url = "github:GrimOutlook/nix-host-svalbard";
    washington.url = "git+ssh://git@github.com/GrimOutlook/nix-host-washington";
  };

  outputs =
    { self, nixpkgs, deploy-rs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      # `deploy-rs.lib.<system>.activate.nixos` embeds the deploy-rs binary
      # built by the input's own (older) nixpkgs, whose fetchCrate still uses
      # the crates.io API URL that now 403s -- so that activation wrapper is
      # unbuildable anywhere. This is deploy-rs' documented workaround: keep
      # its activation *library*, but take the *binary* from our nixpkgs,
      # where it is cached.
      deployPkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            deploy-rs.overlays.default
            (final: prev: {
              deploy-rs = {
                inherit (import nixpkgs { inherit system; }) deploy-rs;
                inherit (prev.deploy-rs) lib;
              };
            })
          ];
        };

      # The fleet. `system` is the *target's* system, which selects the
      # matching deploy-rs activation library.
      nodes = {
        amsterdam = { system = "x86_64-linux"; };
        berlin = { system = "x86_64-linux"; };

        # aarch64: building on an x86_64 laptop needs either binfmt emulation
        # or `remoteBuild`, which builds on the Pi itself.
        dubai = {
          system = "aarch64-linux";
          remoteBuild = true;
        };

        macao = { system = "x86_64-linux"; };

        # Router/firewall. The whole reason for adopting deploy-rs: a bad
        # nftables change here severs the SSH path you would fix it over.
        newyork = {
          system = "x86_64-linux";
          confirmTimeout = 120;
        };

        oslo = { system = "x86_64-linux"; };

        # paris is this laptop -- deploying to it over SSH makes little
        # sense, and `sudo -n` fails there anyway. Left out on purpose;
        # keep using `sudo nixos-rebuild switch` locally.
        # paris = { system = "x86_64-linux"; };

        pyongyang = { system = "x86_64-linux"; };

        # Physically remote: no keyboard to plug in, so rollback matters.
        svalbard = {
          system = "x86_64-linux";
          confirmTimeout = 120;
        };

        washington = { system = "x86_64-linux"; };
      };

      mkNode =
        name:
        {
          system,
          sshUser ? "root",
          hostname ? name,
          remoteBuild ? false,
          confirmTimeout ? 30,
        }:
        {
          inherit hostname sshUser;

          # Activate, then require the deployer to reconnect within
          # `confirmTimeout` seconds -- otherwise the host rolls itself back
          # to the previous generation.
          magicRollback = true;
          autoRollback = true;
          inherit confirmTimeout;

          profiles.system = {
            user = "root";
            path = (deployPkgsFor system).deploy-rs.lib.activate.nixos
              inputs.${name}.nixosConfigurations.${name};
            inherit remoteBuild;
          };
        };
    in
    {
      deploy.nodes = lib.mapAttrs mkNode nodes;

      # Fails the check if a node's profile does not evaluate or its
      # activation script is malformed. This is the schema validation the
      # commented-out `deployChecks` in nix-config was reaching for.
      checks = builtins.mapAttrs (_: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
