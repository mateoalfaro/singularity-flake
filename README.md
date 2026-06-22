# singularity-flake
A Nix Flake to use the in development singularity desktop.

## Usage

```sh
# Run directly without installing
nix run github:mateoalfaro/singularity-flake

# Or build it
nix build github:mateoalfaro/singularity-flake
```

## NixOS module

Add the flake to your inputs and enable it with a single option:

```nix
{
  inputs.singularity-desktop.url = "github:mateoalfuro/singularity-flake";

  outputs = { self, nixpkgs, singularity-desktop, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        singularity-desktop.nixosModules.default
      ];
    };
  };
}
```

## Configuration

```nix
{
  programs.singularity-desktop = {
    enable = true;
    greeter = {
      enable = true;   # enables the Singularity greeter via greetd (disabled by default)
      #You can also customize greetd by replacing the default background image
      #background = "/path/to/image.jpg";
    };
  };
}
```

## Inputs

- `nixpkgs` — pinned to `nixos-unstable`.
- `labwc-src` — tracks the latest commit of [singularityos-lab/labwc](https://github.com/singularityos-lab/labwc).
- `singularity-desktop-src` — tracks the latest commit of [singularityos-lab/singularity-desktop](https://github.com/singularityos-lab/singularity-desktop) (with submodules).

## Auto-update

A daily GitHub Action (`.github/workflows/update-flake-lock.yml`) runs
`nix flake update` and opens a Pull Request with the bumped `flake.lock`.

To update manually at any time:

```sh
nix flake update
```
