# singularity-flake
A Nix Flake to use the in development singularity desktop.

## Usage

```sh
# Run the packaged Singularity Desktop binary directly without installing.
# This is useful for quick experiments, but it is not a full display-manager
# session.
nix run github:mateoalfaro/singularity-flake

# Build the package
nix build github:mateoalfaro/singularity-flake
```

## NixOS module

For a real desktop session, use the NixOS module. Add the flake to your inputs
and enable it with a single option:

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
the existing `greetd` session will still be present in `tty1/tty2`.
Reboot for the old session to disappear.
This appears to be intended greetd behavior and cannot be fixed by this flake.

For display manager changes such as `greetd` <-> `gdm`, prefer one of these:

- use `nixos-rebuild boot` and reboot
- run `nixos-rebuild switch` from another TTY or over SSH
- after switching, move to the VT where the new display manager started
  (commonly `Ctrl`+`Alt`+`F2` or `Ctrl`+`Alt`+`F3`)

### Custom package requirements

`programs.singularity-desktop.package` can be overridden, but the replacement
package must provide the same runtime interface as the default package:

- `bin/singularity-labwc-session`
- `bin/singularity-desktop-session`
- `bin/labwc`
- the greeter executables used by the module
- Wayland session metadata under `share/wayland-sessions`
- xdg-desktop-portal metadata and services
- `passthru.providedSessions`

## Inputs

- `nixpkgs` — pinned to `nixos-unstable`.
- `labwc-src` — tracks the latest commit of [singularityos-lab/labwc](https://github.com/singularityos-lab/labwc).
- `singularity-desktop-src` — tracks the latest commit of [singularityos-lab/singularity-desktop](https://github.com/singularityos-lab/singularity-desktop) (with submodules).

## Updating inputs

To update inputs manually:

```sh
nix flake update
```
