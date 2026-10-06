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

    # Newer Meson rejects nested ternary expressions. Rewrite the
    # test-source selection with if/elif so the suite still configures.
    patch -p1 <<'TEST_SOURCES_EOF'
--- a/t/meson.build	2026-10-06 12:53:13.116259500 -0600
+++ b/t/meson.build	2026-10-06 12:53:20.570884680 -0600
@@ -31,17 +31,24 @@
 ]
 
 foreach t : tests
+  if t == 'gesture'
+    test_sources = [
+      '@0@.c'.format(t),
+      '../src/config/gesturebind.c',
+    ]
+  elif t == 'pressure-curve'
+    test_sources = [
+      '@0@.c'.format(t),
+      '../src/config/tablet-tool.c',
+    ]
+  else
+    test_sources = ['@0@.c'.format(t)]
+  endif
   test(
     'test_@0@'.format(t),
     executable(
       'test_@0@'.format(t),
-      sources: t == 'gesture' ? [
-        '@0@.c'.format(t),
-        '../src/config/gesturebind.c',
-      ] : t == 'pressure-curve' ? [
-        '@0@.c'.format(t),
-        '../src/config/tablet-tool.c',
-      ] : '@0@.c'.format(t),
+      sources: test_sources,
       include_directories: [labwc_inc],
       link_with: [test_lib],
       dependencies: t in ['gesture', 'pressure-curve'] ? test_deps + [math] : test_deps,
TEST_SOURCES_EOF
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
