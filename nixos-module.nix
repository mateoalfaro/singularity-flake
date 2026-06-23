self: { lib, config, pkgs, ... }:

let
  cfg = config.programs.singularity-desktop;
  gcfg = cfg.greeter;

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

  greeter-session = pkgs.writeShellScript "singularity-greeter-session" ''
    export GDK_BACKEND=wayland
    export GSK_RENDERER=gl
    export GTK_A11Y=none
    export SINGULARITY_GREETER_SESSION_DIR="${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
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
in {
  options.programs.singularity-desktop = {
    enable = lib.mkEnableOption "Singularity Desktop Environment";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      defaultText = lib.literalExpression "inputs.singularity-desktop.packages.\${pkgs.system}.default";
      description = ''
        The singularity-desktop package to use. Defaults to the package
        provided by this flake.
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

  config = lib.mkIf cfg.enable {
    services.displayManager.sessionPackages = [ cfg.package ];

    systemd.packages = [ cfg.package ];

    xdg.portal = {
      enable = true;
      extraPortals = [ cfg.package ];
      config.Singularity.default = [ "singularity" "gtk" ];
    };

    # Auto-enable accounts-daemon when the greeter is on so this works out of the box (still overridable).
    services.accounts-daemon.enable =
      lib.mkIf gcfg.enable (lib.mkDefault true);

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
        assertion = !(gcfg.enable
          && ((config.services.displayManager.gdm.enable or false)
              || (config.services.displayManager.sddm.enable or false)
              || (config.services.xserver.displayManager.lightdm.enable or false)));
        message = ''
          singularity-desktop.greeter launches its greeter through greetd,
          which must own VT 1. Disable your current display manager
          (services.displayManager.{gdm,sddm,lightdm}.enable = false)
          before enabling the greeter.
        '';
      }
    ];
  };
}
