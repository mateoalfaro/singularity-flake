# singularity-flake
A Nix Flake to use the in development singularity desktop.

## Usage

```sh
# Run directly without installing
nix run github:mateoalfuro/singularity-flake

# Or build it
nix build github:mateoalfuro/singularity-flake
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
