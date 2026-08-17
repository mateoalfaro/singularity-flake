{
  self,
  nixpkgs,
  system,
  applicationIds,
}:

let
  pkgs = nixpkgs.legacyPackages.${system};
  cacheSubstituter = "https://singularity-flake.cachix.org";
  cachePublicKey =
    "singularity-flake.cachix.org-1:VuMgdHdcA0CNCZiX05SEqR/e78PGf3obmZI/2zI4CEo=";
  appIdsFrom =
    configuration:
    map (application: application.passthru.singularityAppId) (
      builtins.filter (
        application: application ? passthru.singularityAppId
      ) configuration.environment.systemPackages
    );
  evaluate =
    module:
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.default
        { system.stateVersion = "26.05"; }
        module
      ];
    }).config;
  defaultConfiguration = evaluate {
    programs.singularity-desktop.enable = true;
  };
  cacheDisabledConfiguration = evaluate {
    programs.singularity-desktop.enable = true;
    singularity-flake.cache.enable = false;
  };
  excludedConfiguration = evaluate (
    { pkgs, ... }: {
      programs.singularity-desktop = {
        enable = true;
        excludePackages = with pkgs; [
          singularity-calculator
          singularity-music
        ];
      };
    }
  );
  experimentalConfiguration =
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.experimental
        { system.stateVersion = "26.05"; }
        ({ pkgs, ... }: {
          programs.singularity-desktop = {
            enable = true;
            excludePackages = with pkgs; [
              singularity-calculator
              singularity-music
            ];
          };
        })
      ];
    }).config;
  customConfiguration = evaluate {
    programs.singularity-desktop = {
      enable = true;
      package = pkgs.writeShellScriptBin "custom-singularity-desktop" "exit 0";
      excludePackages = [ self.packages.${system}.singularity-calculator ];
    };
  };
  defaultIds = appIdsFrom defaultConfiguration;
  excludedIds = appIdsFrom excludedConfiguration;
  experimentalIds = appIdsFrom experimentalConfiguration;
  failedCustomAssertions = builtins.filter (
    assertion: !assertion.assertion
  ) customConfiguration.assertions;
  singularitySessionTarget = defaultConfiguration.systemd.user.targets.singularity-session;
  applicationPackages = map (id: self.packages.${system}."singularity-${id}") applicationIds;
in
{
  module-options =
    assert self.packages.${system}.default.meta.mainProgram == "singularity-desktop";
    assert builtins.elem cacheSubstituter (
      defaultConfiguration.nix.settings.extra-substituters or [ ]
    );
    assert builtins.elem cachePublicKey (
      defaultConfiguration.nix.settings.extra-trusted-public-keys or [ ]
    );
    assert !(builtins.elem cacheSubstituter (
      cacheDisabledConfiguration.nix.settings.extra-substituters or [ ]
    ));
    assert !(builtins.elem cachePublicKey (
      cacheDisabledConfiguration.nix.settings.extra-trusted-public-keys or [ ]
    ));
    assert
      self.packages.${system}.default.passthru.labwcPackage.outPath
      != self.packages.${system}.experimental.passthru.labwcPackage.outPath;
    assert builtins.length defaultIds == builtins.length applicationIds;
    assert builtins.all (id: builtins.elem id defaultIds) applicationIds;
    assert builtins.length excludedIds == builtins.length applicationIds - 2;
    assert !(builtins.elem "calculator" excludedIds);
    assert !(builtins.elem "music" excludedIds);
    assert builtins.length experimentalIds == builtins.length applicationIds - 2;
    assert !(builtins.elem "calculator" experimentalIds);
    assert !(builtins.elem "music" experimentalIds);
    assert builtins.length failedCustomAssertions >= 1;
    assert singularitySessionTarget.bindsTo == [ "graphical-session.target" ];
    assert singularitySessionTarget.wants == [ "graphical-session-pre.target" ];
    pkgs.runCommand "singularity-desktop-module-options" { } ''
      touch $out
    '';

  cached-packages =
    pkgs.runCommand "singularity-desktop-cached-packages"
      {
        paths = builtins.attrValues self.packages.${system};
      }
      ''
        mkdir -p $out
        echo "Cached all singularity-desktop packages ($(echo "$paths" | wc -w) store paths)"
      '';

  package-layout =
    pkgs.runCommand "singularity-desktop-package-layout"
      {
        core = self.packages.${system}.singularity-desktop-core;
        calculator = self.packages.${system}.singularity-calculator;
        calendar = self.packages.${system}.singularity-calendar;
        files = self.packages.${system}.singularity-files;
        git = self.packages.${system}.singularity-git;
        store = self.packages.${system}.singularity-store;
        write = self.packages.${system}.singularity-write;
        aggregate = self.packages.${system}.default;
        applications = pkgs.lib.concatStringsSep " " applicationPackages;
      }
      ''
        app_ids=(${pkgs.lib.concatStringsSep " " applicationIds})
        app_paths=($applications)

        for index in "''${!app_ids[@]}"; do
          app_id="''${app_ids[$index]}"
          app_path="''${app_paths[$index]}"

          test ! -e "$core/bin/singularity-$app_id"
          test -x "$aggregate/bin/singularity-$app_id"

          # Every split application wrapper must expose its own data directory.
          grep -aF "$app_path/share" "$app_path/bin/singularity-$app_id" >/dev/null

          # Outputs that ship a schema must also ship their compiled database.
          if find "$app_path/share/glib-2.0/schemas" \
            -name '*.gschema.xml' -print -quit 2>/dev/null | grep -q .; then
            test -e "$app_path/share/glib-2.0/schemas/gschemas.compiled"
          fi
        done

        test -f "$core/bin/.singularity-desktop-session-wrapped"
        if grep -F 'export GSETTINGS_SCHEMA_DIR=' \
          "$core/bin/.singularity-desktop-session-wrapped"; then
          echo "singularity-desktop-session exports GSETTINGS_SCHEMA_DIR" >&2
          exit 1
        fi
        test ! -e "$core/share/applications/dev.sinty.calculator.desktop"
        test -x "$calculator/bin/singularity-calculator"
        test -e "$calculator/share/applications/dev.sinty.calculator.desktop"
        test "$(readlink -f "$calculator/share/applications/mimeinfo.cache")" != \
          "$(readlink -f "$core/share/applications/mimeinfo.cache")"
        test "$(readlink -f "$calendar/share/glib-2.0/schemas/gschemas.compiled")" != \
          "$(readlink -f "$core/share/glib-2.0/schemas/gschemas.compiled")"
        test -e "$files/share/icons/hicolor/scalable/apps/ush-penguin.svg"
        test -e "$files/share/icons/hicolor/scalable/apps/ush-penguin-symbolic.svg"
        test ! -e "$core/share/icons/hicolor/scalable/apps/ush-penguin.svg"
        test ! -e "$core/share/icons/hicolor/scalable/apps/ush-penguin-symbolic.svg"

        # The shell owns ~/.config/labwc. Pinning -C makes labwc ignore its
        # generated keybindings, cursor environment and theme overrides.
        labwc_session="$core/bin/.singularity-labwc-session-wrapped"
        test -f "$labwc_session"
        if grep -F -- ' -C ' "$labwc_session" >/dev/null; then
          echo "singularity-labwc-session still pins a -C config directory" >&2
          exit 1
        fi

        desktop_session="$core/bin/.singularity-desktop-session-wrapped"
        grep -F -- 'systemctl --user start singularity-session.target' \
          "$desktop_session" >/dev/null
        grep -F -- 'systemctl --user stop singularity-session.target' \
          "$desktop_session" >/dev/null

        # Core command providers must be embedded in the session PATH.
        for provider in \
          "${pkgs.bash}/bin" \
          "${pkgs.networkmanager}/bin" \
          "${pkgs.wl-clipboard}/bin" \
          "${pkgs.libnotify}/bin" \
          "${pkgs.hyprpicker}/bin"; do
          grep -aF "$provider" "$labwc_session" >/dev/null
        done

        # Verify the source-level absolute data paths were replaced by Nix
        # store paths in the built core.
        for fixed_path in \
          "${pkgs.glibcLocales}/share/i18n/SUPPORTED" \
          "${pkgs.tzdata}/share/zoneinfo" \
          "${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.lst"; do
          grep -R -aF "$fixed_path" "$core" >/dev/null
        done

        # Split application wrappers expose only the runtime tools they need.
        grep -aF "${pkgs.git}/bin" "$git/bin/singularity-git" >/dev/null
        grep -aF "${pkgs.flatpak}/bin" "$store/bin/singularity-store" >/dev/null
        for provider in "${pkgs.bash}/bin" "${pkgs.zip}/bin" "${pkgs.coreutils}/bin"; do
          grep -aF "$provider" "$write/bin/singularity-write" >/dev/null
        done
        for provider in "${pkgs.libarchive}/bin" "${pkgs.unzip}/bin" "${pkgs.gnutar}/bin" "${pkgs.zip}/bin"; do
          grep -aF "$provider" "$files/bin/singularity-files" >/dev/null
        done

        # The nested session startup script must use Nix's Bash interpreter.
        grep -R -aF "${pkgs.bash}/bin/bash" "$core/bin" >/dev/null
        if grep -R -aF '#!/bin/bash' "$core/bin" >/dev/null; then
          echo "literal /bin/bash shebang remains in the core" >&2
          exit 1
        fi
        test -x "$aggregate/bin/singularity-desktop"
        touch $out
      '';
}
