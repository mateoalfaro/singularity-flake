{
  self,
  nixpkgs,
  system,
  applicationIds,
}:

let
  pkgs = nixpkgs.legacyPackages.${system};
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
in
{
  module-options =
    assert builtins.length defaultIds == builtins.length applicationIds;
    assert builtins.all (id: builtins.elem id defaultIds) applicationIds;
    assert builtins.length excludedIds == builtins.length applicationIds - 2;
    assert !(builtins.elem "calculator" excludedIds);
    assert !(builtins.elem "music" excludedIds);
    assert builtins.length experimentalIds == builtins.length applicationIds - 2;
    assert !(builtins.elem "calculator" experimentalIds);
    assert !(builtins.elem "music" experimentalIds);
    assert builtins.length failedCustomAssertions >= 1;
    pkgs.runCommand "singularity-desktop-module-options" { } ''
      touch $out
    '';

  package-layout =
    pkgs.runCommand "singularity-desktop-package-layout"
      {
        core = self.packages.${system}.singularity-desktop-core;
        calculator = self.packages.${system}.singularity-calculator;
        calendar = self.packages.${system}.singularity-calendar;
        aggregate = self.packages.${system}.default;
      }
      ''
        for app_id in ${pkgs.lib.concatStringsSep " " applicationIds}; do
          test ! -e "$core/bin/singularity-$app_id"
          test -x "$aggregate/bin/singularity-$app_id"
        done
        test ! -e "$core/share/applications/dev.sinty.calculator.desktop"
        test -x "$calculator/bin/singularity-calculator"
        test -e "$calculator/share/applications/dev.sinty.calculator.desktop"
        test "$(readlink -f "$calculator/share/applications/mimeinfo.cache")" != \
          "$(readlink -f "$core/share/applications/mimeinfo.cache")"
        test "$(readlink -f "$calendar/share/glib-2.0/schemas/gschemas.compiled")" != \
          "$(readlink -f "$core/share/glib-2.0/schemas/gschemas.compiled")"
        test -x "$aggregate/bin/singularity-desktop"
        touch $out
      '';
}
