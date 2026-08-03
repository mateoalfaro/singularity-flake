{
  pkgs,
  nixpkgs,
  applicationIds,
  inputs,
}:

let
  applicationPackageNames = map (id: "singularity-${id}") applicationIds;
  vetro = import ./vetro.nix { inherit pkgs nixpkgs; };
  defaultLabwc = import ./labwc.nix {
    inherit pkgs nixpkgs;
    src = inputs.labwc-src;
  };
  experimentalLabwc = import ./labwc.nix {
    inherit pkgs nixpkgs;
    src = inputs.labwc-fork;
  };
  makeSingularityDesktop = import ./desktop.nix {
    inherit
      pkgs
      nixpkgs
      applicationIds
      vetro
      ;
    greeterSessionWrapperPatch = ../../patches/singularity-greeter-session-wrapper.patch;
    singularityDesktopRuntimePatch = ../../patches/singularity-desktop-runtime.patch;
  };

  applicationRuntimeProviders = {
    files = with pkgs; [
      libarchive
      unzip
      gnutar
      zip
    ];
    git = [ pkgs.git ];
    store = [ pkgs.flatpak ];
    write = with pkgs; [
      bash
      zip
      coreutils
    ];
  };

  makeApplicationPackages =
    desktop:
    pkgs.lib.genAttrs applicationPackageNames (
      packageName:
      let
        id = pkgs.lib.removePrefix "singularity-" packageName;
        providers = applicationRuntimeProviders.${id} or [ ];
      in
      pkgs.symlinkJoin {
        name = "${packageName}-${desktop.version}";
        paths = [ desktop.${id} ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapper_args=(
            --prefix XDG_DATA_DIRS :
            "$out/share"
          )
          ${pkgs.lib.optionalString (providers != [ ]) ''
            wrapper_args+=(
              --prefix PATH :
              "${pkgs.lib.makeBinPath providers}"
            )
          ''}
          wrapProgram "$out/bin/${packageName}" "''${wrapper_args[@]}"
        '';
        passthru.singularityAppId = id;
        meta = desktop.meta // {
          description = "${packageName} application from Singularity Desktop";
          mainProgram = packageName;
        };
      }
    );

  makeAggregate =
    desktop: applications:
    pkgs.symlinkJoin {
      name = "${desktop.pname}-${desktop.version}";
      paths = [ desktop ] ++ pkgs.lib.attrValues applications;
      passthru = desktop.passthru // {
        inherit applications;
      };
      meta = desktop.meta;
      postBuild = ''
        if [ -d "$out/share/glib-2.0/schemas" ]; then
          rm -f "$out/share/glib-2.0/schemas/gschemas.compiled"
          ${pkgs.glib.dev}/bin/glib-compile-schemas "$out/share/glib-2.0/schemas"
        fi
        if [ -d "$out/share/applications" ]; then
          rm -f "$out/share/applications/mimeinfo.cache"
          ${pkgs.desktop-file-utils}/bin/update-desktop-database "$out/share/applications"
        fi
      '';
    };

  defaultDesktop = makeSingularityDesktop {
    src = inputs.singularity-desktop-src;
    labwcPackage = defaultLabwc;
  };
  defaultApplications = makeApplicationPackages defaultDesktop;

  experimentalDesktop = makeSingularityDesktop {
    pname = "singularity-desktop-experimental";
    labwcPackage = experimentalLabwc;
    src = pkgs.runCommand "singularity-desktop-experimental-src" { } ''
      cp -R --no-preserve=mode,ownership ${inputs.singularity-desktop-src}/. $out

      rm -rf $out/subprojects/singularity-shell
      cp -R --no-preserve=mode,ownership ${inputs.singularity-shell-src} $out/subprojects/singularity-shell

      rm -rf $out/subprojects/singularity-session
      cp -R --no-preserve=mode,ownership ${inputs.singularity-session-src} $out/subprojects/singularity-session

      rm -rf $out/subprojects/xdg-desktop-portal-singularity
      cp -R --no-preserve=mode,ownership ${inputs.xdg-desktop-portal-singularity-src} $out/subprojects/xdg-desktop-portal-singularity

      rm -rf $out/subprojects/labwc
      cp -R --no-preserve=mode,ownership ${inputs.labwc-fork} $out/subprojects/labwc
    '';
  };
  experimentalApplications = makeApplicationPackages experimentalDesktop;
in
{
  default = makeAggregate defaultDesktop defaultApplications;
  experimental = makeAggregate experimentalDesktop experimentalApplications;
  singularity-desktop-core = defaultDesktop;
  singularity-desktop-experimental-core = experimentalDesktop;
}
// defaultApplications
// pkgs.lib.mapAttrs' (
  name: value: pkgs.lib.nameValuePair "${name}-experimental" value
) experimentalApplications
