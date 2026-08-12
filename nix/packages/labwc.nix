{
  pkgs,
  nixpkgs,
  src,
}:

pkgs.stdenv.mkDerivation {
  pname = "singularity-labwc";
  version = "0-unstable-2026-06-15";

  inherit src;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    wayland-scanner
    gettext
    scdoc
  ];

  buildInputs = with pkgs; [
    wlroots_0_20
    wayland
    wayland-protocols
    libxkbcommon
    libxcb
    libxcb-wm
    libxml2
    glib
    cairo
    pango
    libdrm
    libinput
    pixman
    libpng
    librsvg
    libsfdo
    xwayland
  ];

  mesonFlags = [
    "-Dxwayland=enabled"
    "-Dsystemd-session=disabled"
  ];

  meta = {
    description = "Singularity fork of labwc (preview / tiling / blur Wayland protocols)";
    homepage = "https://github.com/singularityos-lab/labwc";
    license = nixpkgs.lib.licenses.gpl2Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "labwc";
  };
}
