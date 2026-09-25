{
  pkgs,
  nixpkgs,
  src,
}:

pkgs.stdenv.mkDerivation {
  pname = "singularity-labwc";
  version = "0-unstable-2026-09-13";

  inherit src;

  # The fork's gesture test includes config/rcxml.h, which includes cairo and
  # pango headers, but its Meson test dependency list omits both.
  postPatch = ''
    substituteInPlace t/meson.build \
      --replace-fail \
        $'  wlroots,\n]' \
        $'  wlroots,\n  wayland_server,\n  cairo,\n  pangocairo,\n]'
  '';

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    pkg-config
    wayland-scanner
    gettext
    scdoc
  ];

  nativeCheckInputs = [ pkgs.cmocka ];

  buildInputs = with pkgs; [
    wlroots_0_20
    wayland
    wayland-protocols
    libxkbcommon
    libxcb
    libglvnd
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
    "-Dtest=enabled"
  ];

  doCheck = true;

  meta = {
    description = "Singularity fork of labwc (preview / tiling / blur Wayland protocols)";
    homepage = "https://github.com/singularityos-lab/labwc";
    license = nixpkgs.lib.licenses.gpl2Plus;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "labwc";
  };
}
