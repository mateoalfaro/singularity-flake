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
  inputs.singularity-desktop.url = "github:mateoalfaro/singularity-flake";

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

When `programs.singularity-desktop.greeter.enable = true`, your desktop session
is started by `greetd` on `tty1`. If you later switch to another display
manager such as GDM with `nixos-rebuild switch` while still logged into that session, 
the existing `greetd` session will still be present in `tty1/tty2`, 
in order for the session to dissapear you will need to reboot. 
This apparently is intended greetd behavior and can not be fixed by me.

For display manager changes such as `greetd` <-> `gdm`, prefer one of these:

- use `nixos-rebuild boot` and reboot
- run `nixos-rebuild switch` from another TTY or over SSH
- after switching, move to the VT where the new display manager started
  (commonly `Ctrl`+`Alt`+`F2` or `Ctrl`+`Alt`+`F3`)

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
