self: { lib, config, pkgs, ... }:

let
  cfg = config.programs.singularity-desktop;
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
  };

  config = lib.mkIf cfg.enable {
    services.displayManager.sessionPackages = [ cfg.package ];

    systemd.packages = [ cfg.package ];

    xdg.portal = {
      enable = true;
      extraPortals = [ cfg.package ];
      config.Singularity.default = [ "singularity" "gtk" ];
    };
  };
}
