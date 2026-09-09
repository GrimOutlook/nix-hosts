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
    # Security NVR host. Private, hence ssh.
    dunkirk.url = "git+ssh://git@github.com/GrimOutlook/nix-host-dunkirk";
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

        # aarch64: the fleet defaults to building on the target, so the Pi
        # builds its own system instead of requiring cross-compilation or
        # binfmt emulation on the deployer.
        dubai = {
          system = "aarch64-linux";
        };

        macao = { system = "x86_64-linux"; };

        # Router/firewall. Build locally because this machine is not powerful
        # enough to be a useful build host. The whole reason for adopting
        # deploy-rs: a bad nftables change here severs the SSH path you would
        # fix it over.
        newyork = {
          system = "x86_64-linux";
          remoteBuild = false;
          confirmTimeout = 120;
        };

        oslo = { system = "x86_64-linux"; };

        # paris is this laptop -- deploying to it over SSH makes little
        # sense, and `sudo -n` fails there anyway. Left out on purpose;
        # keep using `sudo nixos-rebuild switch` locally.
        # paris = { system = "x86_64-linux"; };

        dunkirk = { system = "x86_64-linux"; };

        # Physically remote: no keyboard to plug in, so rollback matters.
        svalbard = {
          system = "x86_64-linux";
          confirmTimeout = 120;
        };

        washington = { system = "x86_64-linux"; };
      };

      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # `--rollback-succeeded false` has no flake attribute: deploy-rs reads it
      # only from the command-line opts (`cli.rs`), never from deploy data --
      # its `GenericSettings` schema carries just `autoRollback` and
      # `magicRollback`. So the default is set here, in a wrapper.
      #
      # Upstream defaults it to `true`, meaning if the seventh host fails to
      # *activate*, deploy-rs reverts the six that already succeeded. For a
      # fleet of unrelated machines that is backwards: a bad Frigate config on
      # pyongyang should not roll back a good newyork. Each host still rolls
      # *itself* back on failure via magicRollback/autoRollback.
      #
      # The flag is injected only when absent: clap rejects a repeated
      # `--rollback-succeeded` ("cannot be used multiple times") rather than
      # letting the last one win, so appending it unconditionally would make
      # the option impossible to override.
      mkDeploy =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.writeShellApplication {
          name = "deploy";
          # Called by full path, not via runtimeInputs: this wrapper is itself
          # named `deploy`, so putting the real one on PATH would recurse.
          text = ''
            for arg in "$@"; do
              case "$arg" in
                # Everything past `--` is passed through to `nix build`.
                --) break ;;
                --rollback-succeeded | --rollback-succeeded=*)
                  exec ${pkgs.deploy-rs}/bin/deploy "$@" ;;
              esac
            done
            exec ${pkgs.deploy-rs}/bin/deploy --rollback-succeeded false "$@"
          '';
        };

      mkNode =
        name:
        {
          system,
          sshUser ? "root",
          hostname ? name,
          remoteBuild ? true,
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

      # `nix run . -- .` deploys the fleet; `nix develop` puts the same wrapper
      # on PATH as plain `deploy`.
      #
      # Deliberately NOT named `deploy`: deploy-rs reads its node data by
      # evaluating `<flake>#deploy` (cli.rs), and Nix resolves that to
      # `packages.<system>.deploy` in preference to the top-level `deploy`
      # output -- so a package by that name hides the fleet from the tool.
      packages = forAllSystems (system: rec {
        deploy-fleet = mkDeploy system;
        default = deploy-fleet;
      });

      apps = forAllSystems (system: rec {
        deploy-fleet = {
          type = "app";
          program = lib.getExe (mkDeploy system);
        };
        default = deploy-fleet;
      });

      devShells = forAllSystems (system: {
        default = (import nixpkgs { inherit system; }).mkShellNoCC {
          packages = [ (mkDeploy system) ];
        };
      });

      # Fails the check if a node's profile does not evaluate or its
      # activation script is malformed. This is the schema validation the
      # commented-out `deployChecks` in nix-config was reaching for.
      checks = builtins.mapAttrs (_: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
