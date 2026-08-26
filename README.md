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

## NixOS module (experimental)
You can also use the experimental module to replace some subprojects with my own forked versions, in order to help me test new features or bug fixes.

```nix
{
  nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      singularity-desktop.nixosModules.experimental
    ];
  };
}
```

The experimental module uses the same NixOS options as the default module, but
its default package currently replaces these subprojects in the Singularity Desktop source
tree:

- `subprojects/singularity-shell`
- `subprojects/singularity-session`
- `subprojects/xdg-desktop-portal-singularity`
- `subprojects/labwc`

## Configuration

```nix
{
  programs.singularity-desktop = {
    enable = true;

    # Optional: you can also exclude bundled applications from the system profile.
    excludePackages = with pkgs; [
      singularity-calculator
      singularity-music
      singularity-store
    ];

    # Or remove every bundled app at once without listing them:
    core-apps.enable = false;

    greeter = {
      enable = true;   # enables the Singularity greeter via greetd (disabled by default)
      #You can also customize greetd by replacing the default background image
      #background = "/path/to/image.jpg";
    };

  };

  # The Singularity Cachix binary cache is enabled by default. Set this to
  # false if you do not want to use or trust it.
  # singularity-flake.cache.enable = false;
}
```

Importing either Singularity NixOS module enables the project's Cachix binary
cache by default. To opt out, set `singularity-flake.cache.enable = false`.
The cache setting is independent of `programs.singularity-desktop.enable`.

`programs.singularity-desktop.excludePackages` accepts package values, like
`environment.gnome.excludePackages`. Importing either Singularity NixOS module
adds an overlay that exposes these default applications under `pkgs`:

- `singularity-files`
- `singularity-calculator`
- `singularity-calendar`
- `singularity-edit`
- `singularity-git`
- `singularity-leafs`
- `singularity-monitor`
- `singularity-music`
- `singularity-photos`
- `singularity-store`
- `singularity-videos`
- `singularity-write`

`programs.singularity-desktop.core-apps.enable` (default `true`): setting it to `false` drops every extra bundled
application from the system profile by default.

The desktop session, shell, greeter, portal, themes, wallpapers, and other required desktop
infrastructure are kept in the core package and cannot be excluded.

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
- xdg-desktop-portal metadata and services, including a desktop-specific
  config at `share/xdg-desktop-portal/<desktop>-portals.conf`
- `passthru.providedSessions`

The portal configuration must be scoped to the package's desktop name. The
module installs the package as an additional portal implementation and uses a
low-priority `xdg.portal.configPackages` entry, so GNOME, KDE, Hyprland, Niri,
and other desktop modules can retain their own portal configuration when they
are used instead of Singularity. A replacement package must not provide a
generic `share/xdg-desktop-portal/portals.conf` that changes portal selection
for every desktop.

## Inputs

- `nixpkgs` — pinned to `nixos-unstable`.
- `labwc-src` — tracks the latest commit of [singularityos-lab/labwc](https://github.com/singularityos-lab/labwc).
- `singularity-desktop-src` — tracks the latest commit of [singularityos-lab/singularity-desktop](https://github.com/singularityos-lab/singularity-desktop) (with submodules).


- `singularity-shell-src` — tracks `git@github.com:mateoalfaro/singularity-shell.git` for `packages.experimental` and `nixosModules.experimental`.
- `singularity-session-src` — tracks `git@github.com:mateoalfaro/singularity-session.git` for `packages.experimental` and `nixosModules.experimental`.
- `xdg-desktop-portal-singularity-src` — tracks `git@github.com:mateoalfaro/xdg-desktop-portal-singularity.git` for `packages.experimental` and `nixosModules.experimental`.
- `labwc-fork` — tracks `git@github.com:mateoalfaro/labwc.git` for `packages.experimental` and `nixosModules.experimental`.

## Updating inputs

To update inputs manually:

```sh
nix flake update
```
