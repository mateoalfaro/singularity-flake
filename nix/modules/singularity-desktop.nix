{
  package,
  applications,
  overlay,
  defaultText,
}:
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.programs.singularity-desktop;
  gcfg = cfg.greeter;
  defaultPackage = package pkgs;
  defaultApplications = applications pkgs;
  usingDefaultPackage = cfg.package == defaultPackage;
  applicationId = application: application.passthru.singularityAppId or (lib.getName application);
  excludedApplicationIds = map applicationId cfg.excludePackages;
  enabledDefaultApplications = lib.filter (
    application: !(lib.elem (applicationId application) excludedApplicationIds)
  ) defaultApplications;
  displayManagerXdgDataDirs = lib.concatStringsSep ":" (
    lib.filter (s: s != "") [
      "${config.services.displayManager.sessionData.desktops}/share"
      "/run/current-system/sw/share"
      (toString (config.services.displayManager.generic.environment.XDG_DATA_DIRS or ""))
    ]
  );

  # Shared VM cursor detection
  vmCursorProbe = ''
    for drv in /sys/class/drm/card[0-9]*/device/driver; do
        [ -e "$drv" ] || continue
        case "$(basename "$(readlink -f "$drv")")" in
            virtio*|qxl|vmwgfx|bochs-drm|cirrus|vboxvideo|simpledrm)
                export WLR_NO_HARDWARE_CURSORS="''${WLR_NO_HARDWARE_CURSORS:-1}"
                break ;;
        esac
    done
  '';

  session-launcher = pkgs.writeShellScript "singularity-greeter-session-launcher" ''
    if [ "$#" -ne 1 ]; then
      echo "singularity-greeter-session-launcher: expected one desktop file argument, got $#" >&2
      exit 1
    fi

    desktop_file="$1"
    if [ -z "$desktop_file" ] || [ ! -r "$desktop_file" ]; then
      echo "singularity-greeter-session-launcher: unreadable session file: $desktop_file" >&2
      exit 1
    fi

    desktop_key() {
      ${pkgs.gawk}/bin/awk -F= -v key="$1" '
        /^\[/ { in_desktop = ($0 == "[Desktop Entry]"); next }
        in_desktop && $1 == key {
          sub(/^[^=]*=/, "")
          print
          exit
        }
      ' "$desktop_file"
    }

    set_var_names() {
      _set_vars=
      for _var_name in "$@"; do
        [ -n "''${!_var_name+x}" ] || continue
        _set_vars="''${_set_vars:+$_set_vars }$_var_name"
      done
      printf '%s\n' "$_set_vars"
    }

    exec_line="$(desktop_key Exec || true)"
    desktop_names="$(desktop_key DesktopNames || true)"
    session_name="$(desktop_key Name || true)"
    session_id="$(${pkgs.coreutils}/bin/basename "$desktop_file" .desktop)"

    if [ -z "$exec_line" ]; then
      echo "singularity-greeter-session-launcher: missing Exec in $desktop_file" >&2
      exit 1
    fi

    if [ -z "$desktop_names" ]; then
      desktop_names="$session_id"
    fi

    current_desktop="$(printf '%s\n' "$desktop_names" \
      | ${pkgs.gnused}/bin/sed -e 's/;*$//' -e 's/;/:/g')"
    if [ -z "$current_desktop" ]; then
      current_desktop="$session_id"
    fi

    clean_exec="$(printf '%s\n' "$exec_line" \
      | ${pkgs.gnused}/bin/sed \
          -e 's/%%/__SINGULARITY_GREETER_PERCENT__/g' \
          -e 's/[[:space:]]*%[fFuUick]//g' \
          -e 's/__SINGULARITY_GREETER_PERCENT__/%/g')"

    if [ -r /etc/profile ]; then
      . /etc/profile
    fi
    if [ -n "''${HOME:-}" ] && [ -r "$HOME/.profile" ]; then
      . "$HOME/.profile"
    fi
    if [ -n "''${HOME:-}" ] && [ -r "$HOME/.xprofile" ]; then
      . "$HOME/.xprofile"
    fi

    # greetd passes start_session.env into PAM before pam_systemd. It clears
    # XDG_SESSION_CLASS before exec, so keep these in the child environment too.
    export XDG_SESSION_TYPE="''${XDG_SESSION_TYPE:-wayland}"
    export XDG_SESSION_CLASS="''${XDG_SESSION_CLASS:-user}"
    export XDG_SESSION_DESKTOP="''${XDG_SESSION_DESKTOP:-$session_id}"
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-$current_desktop}"
    export DESKTOP_SESSION="''${DESKTOP_SESSION:-$session_id}"
    export GDK_BACKEND="''${GDK_BACKEND:-wayland}"

    if [ -n "$session_name" ]; then
      export SINGULARITY_GREETER_SESSION_NAME="$session_name"
    fi

    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:${config.systemd.package}/bin:${pkgs.dbus}/bin:${pkgs.coreutils}/bin''${PATH:+:$PATH}"
    export XDG_CONFIG_DIRS="/etc/xdg''${XDG_CONFIG_DIRS:+:$XDG_CONFIG_DIRS}"
    export XDG_DATA_DIRS="${displayManagerXdgDataDirs}''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

    if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    fi

    import_vars="$(set_var_names \
      PATH XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_SESSION_ID \
      XDG_SESSION_TYPE XDG_SESSION_CLASS XDG_SESSION_DESKTOP \
      XDG_CURRENT_DESKTOP DESKTOP_SESSION DBUS_SESSION_BUS_ADDRESS \
      WAYLAND_DISPLAY DISPLAY GDK_BACKEND)"

    if [ -n "$import_vars" ]; then
      ${config.systemd.package}/bin/systemctl --user import-environment $import_vars || true
    fi

    ${config.systemd.package}/bin/systemctl --user unset-environment \
      LD_LIBRARY_PATH GI_TYPELIB_PATH GSETTINGS_SCHEMA_DIR QT_QPA_PLATFORMTHEME \
      SINGULARITY_GREETER_SESSION_NAME || true

    if [ -n "$import_vars" ]; then
      ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd $import_vars || true
    fi

    ${pkgs.dbus}/bin/dbus-update-activation-environment \
      LD_LIBRARY_PATH= GI_TYPELIB_PATH= GSETTINGS_SCHEMA_DIR= QT_QPA_PLATFORMTHEME= \
      SINGULARITY_GREETER_SESSION_NAME= || true

    echo "singularity-greeter-session-launcher: session=$session_id desktop=$XDG_CURRENT_DESKTOP type=$XDG_SESSION_TYPE class=$XDG_SESSION_CLASS id=''${XDG_SESSION_ID:-unset}" >&2

    exec ${pkgs.runtimeShell} -c "exec $clean_exec"
  '';

  greeter-session = pkgs.writeShellScript "singularity-greeter-session" ''
    export GDK_BACKEND=wayland
    export GSK_RENDERER=gl
    export GTK_A11Y=none
    export SINGULARITY_GREETER_SESSION_DIR="${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
    export SINGULARITY_GREETER_SESSION_LAUNCHER="${session-launcher}"
    ${vmCursorProbe}
    exec "${cfg.package}/bin/singularity-greeter"
  '';

  start-greeter = pkgs.writeShellScript "singularity-start-greeter" ''
    export PATH="${cfg.package}/bin:''${PATH:+:$PATH}"
    ${vmCursorProbe}
    ${lib.optionalString (gcfg.background != null) ''
      export SINGULARITY_GREETER_BACKGROUND="${gcfg.background}"
    ''}
    exec labwc -s ${greeter-session}
  '';
in
{
  options.programs.singularity-desktop = {
    enable = lib.mkEnableOption "Singularity Desktop Environment";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression defaultText;
      description = ''
        The singularity-desktop package to use. Defaults to the package
        provided by this flake. Custom packages must provide the session and
        greeter executables used by this module, including
        <filename>bin/singularity-labwc-session</filename>,
        <filename>bin/labwc</filename>, and the portal/session metadata
        installed by the default package.
      '';
    };

    excludePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        with pkgs; [
          singularity-calculator
          singularity-music
          singularity-store
        ]
      '';
      description = ''
        Packages from the default Singularity application set that should not
        be installed. This option is supported when using the desktop package
        provided by this flake. Packages that are not part of the default
        application set are ignored.
      '';
    };

    greeter = {
      enable = lib.mkEnableOption ''
        the Singularity greeter on top of greetd. This replaces your display
        manager with greetd launching the Singularity greeter; disable any
        active display manager (gdm/sddm/lightdm) when enabling this
      '';

      user = lib.mkOption {
        type = lib.types.str;
        default = "greeter";
        defaultText = lib.literalExpression "''greeter''";
        description = ''
          User under which greetd runs the greeter session. Defaults to
          <literal>greeter</literal>, the user NixOS's
          <option>services.greetd</option> creates automatically. If you set
          this to anything else you are responsible for creating that user
          yourself (NixOS requires exactly one of <option>isSystemUser</option>
          / <option>isNormalUser</option>) and adding it to the
          <literal>video</literal>/<literal>input</literal>/<literal>render</literal>
          groups.
        '';
      };

      background = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Wallpaper image to show as the greeter background. The path is
          copied to the Nix store (world-readable) and exposed to the
          greeter via <literal>SINGULARITY_GREETER_BACKGROUND</literal>. Use
          this when your usual wallpaper lives inside a 0700 home directory
          the <literal>greeter</literal> user cannot read.

          If null, the greeter falls back to the user's AccountsService
          wallpaper (when readable) or the stock Singularity wallpaper.
        '';
      };
    };
  };

  config = lib.mkMerge [
    # Make the default applications available as pkgs.singularity-* so option
    # values can use the same `with pkgs; [ ... ]` style as NixOS's GNOME
    # module. Register the overlay whenever this module is imported so those
    # attributes are also available while evaluating the option values.
    {
      nixpkgs.overlays = [ overlay ];
    }

    (lib.mkIf cfg.enable {
      services.displayManager.sessionPackages = [ cfg.package ];

      environment.systemPackages = lib.mkIf usingDefaultPackage enabledDefaultApplications;

      systemd.packages = [ cfg.package ];

      xdg.portal = {
        enable = true;
        extraPortals = [ cfg.package ];
        config.Singularity.default = [
          "singularity"
          "gtk"
        ];
      };

      # Auto-enable accounts-daemon when the greeter is on so this works out of the box (still overridable).
      services.accounts-daemon.enable = lib.mkIf gcfg.enable (lib.mkDefault true);

      services.greetd = lib.mkIf gcfg.enable {
        enable = true;
        settings = {
          terminal.vt = 1;
          default_session = {
            command = "${start-greeter}";
            user = gcfg.user;
          };
        };
      };

      # NixOS greetd creates `users.users.greeter` with isSystemUser=true and
      # adds it to video+input but not render.
      users.users.greeter = lib.mkIf (gcfg.enable && gcfg.user == "greeter") {
        extraGroups = lib.mkAfter [ "render" ];
      };

      assertions = [
        {
          assertion = usingDefaultPackage || cfg.excludePackages == [ ];
          message = ''
            programs.singularity-desktop.excludePackages is only supported
            with the Singularity desktop package provided by this flake.
            Custom packages are monolithic and cannot have bundled
            applications removed safely.
          '';
        }
        {
          assertion =
            !(
              gcfg.enable
              && (
                (config.services.displayManager.gdm.enable or false)
                || (config.services.displayManager.sddm.enable or false)
                || (config.services.xserver.displayManager.lightdm.enable or false)
              )
            );
          message = ''
            singularity-desktop.greeter launches its greeter through greetd,
            which must own VT 1. Disable your current display manager
            (services.displayManager.{gdm,sddm,lightdm}.enable = false)
            before enabling the greeter.
          '';
        }
      ];
    })
  ];
}
