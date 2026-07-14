{
  description = "Singularity Desktop — A Wayland desktop environment built on GTK4 and labwc";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    labwc-src = {
      # url = "path:./singularity-desktop/subprojects/labwc"; # Local development
      url = "github:singularityos-lab/labwc";
      flake = false;
    };

    singularity-desktop-src = {
      # url = "path:./singularity-desktop"; # Local development
      url = "git+https://github.com/singularityos-lab/singularity-desktop.git?submodules=1";
      flake = false;
    };

    singularity-shell-src = {
      url = "github:mateoalfaro/singularity-shell";
      flake = false;
    };

    singularity-session-src = {
      url = "github:mateoalfaro/singularity-session";
      flake = false;
    };

    xdg-desktop-portal-singularity-src = {
      url = "github:mateoalfaro/xdg-desktop-portal-singularity";
      flake = false;
    };

    labwc-fork = {
      url = "github:mateoalfaro/labwc?ref=main";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      applicationIds = import ./nix/applications.nix;
      applicationPackageNames = map (id: "singularity-${id}") applicationIds;
    in
    {
      packages = forAllSystems (
        system:
        import ./nix/packages {
          inherit nixpkgs applicationIds inputs;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      );

      checks = forAllSystems (
        system:
        import ./nix/checks {
          inherit
            self
            nixpkgs
            system
            applicationIds
            ;
        }
      );

      overlays.default =
        final: _prev:
        builtins.listToAttrs (
          map (name: {
            inherit name;
            value = self.packages.${final.stdenv.hostPlatform.system}.${name};
          }) applicationPackageNames
        )
        // {
          singularity-desktop = self.packages.${final.stdenv.hostPlatform.system}.default;
          singularity-desktop-core =
            self.packages.${final.stdenv.hostPlatform.system}.singularity-desktop-core;
        };

      nixosModules = {
        default = import ./nix/modules/singularity-desktop.nix {
          package = pkgs: self.packages.${pkgs.stdenv.hostPlatform.system}.singularity-desktop-core;
          applications =
            pkgs: map (name: self.packages.${pkgs.stdenv.hostPlatform.system}.${name}) applicationPackageNames;
          overlay = self.overlays.default;
          defaultText = "inputs.singularity-desktop.packages.\${pkgs.system}.singularity-desktop-core";
        };

        experimental = import ./nix/modules/singularity-desktop.nix {
          package =
            pkgs: self.packages.${pkgs.stdenv.hostPlatform.system}.singularity-desktop-experimental-core;
          applications =
            pkgs:
            map (
              name: self.packages.${pkgs.stdenv.hostPlatform.system}."${name}-experimental"
            ) applicationPackageNames;
          overlay = self.overlays.default;
          defaultText = "inputs.singularity-desktop.packages.\${pkgs.system}.singularity-desktop-experimental-core";
        };
      };
    };
}
