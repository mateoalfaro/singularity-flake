{
  pkgs,
  nixpkgs,
  src,
}:

pkgs.stdenv.mkDerivation {
  pname = "singularity-labwc";
  version = "0-unstable-2026-09-13";

  inherit src;

  # Newer Meson rejects the nested ternary that selects the per-test
  # source lists; the patch rewrites it with if/elif.
  patches = [ ../../patches/labwc-test-sources.patch ];

  # The fork's gesture test includes config/rcxml.h, which includes cairo and
  # pango headers, but its Meson test dependency list omits both.
  postPatch = ''
    # The XWayland scaling code uses the POSIX strtok_r API. Meson builds
    # labwc as strict C11, which hides its declaration without a feature macro.
    substituteInPlace src/xwayland-scale.c \
      --replace-fail \
        '#include <assert.h>' \
        $'#define _POSIX_C_SOURCE 200809L\n#include <assert.h>'

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
    # SceneFX is the fork's scene-graph renderer (blur/glass). Its
    # meson wrap would require network downloads, which the sandbox
    # forbids; the nixpkgs package exposes the same scenefx-0.5.pc.
    scenefx_0_5
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
