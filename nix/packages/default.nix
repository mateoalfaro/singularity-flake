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
in
{
  default = makeAggregate defaultDesktop defaultApplications;
  singularity-desktop-core = defaultDesktop;
}
// defaultApplications
