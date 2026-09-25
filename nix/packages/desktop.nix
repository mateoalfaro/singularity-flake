{
  pkgs,
  nixpkgs,
  applicationIds,
  gestureRuntime,
  vetro,
  greeterSessionWrapperPatch,
  singularityDesktopRuntimePatch,
}:
{
  pname ? "singularity-desktop",
  src,
  labwcPackage,
}:
let
  runtimeBinPath = pkgs.lib.makeBinPath (
    with pkgs;
    [
      bash
      coreutils
      dbus
      hyprpicker
      libnotify
      networkmanager
      procps
      systemd
      wl-clipboard
      xrdb
      xsettingsd
      xdg-user-dirs
    ]
  );

  runtimeLibraryPath = pkgs.lib.makeLibraryPath (
    with pkgs;
    [
      libglvnd
      mesa
    ]
  );
in
pkgs.stdenv.mkDerivation {
  inherit pname src;
  version = "0.1.0";
  outputs = [ "out" ] ++ applicationIds;

  nativeBuildInputs = with pkgs; [
    meson
    ninja
    vala
    pkg-config
    wayland-scanner
    wayland-protocols
    gettext
    gobject-introspection
    wrapGAppsHook4
    qt6.wrapQtAppsHook
    sassc
    python3
    vetro
    desktop-file-utils
  ];

  buildInputs = with pkgs; [
    gtk4
    gtk4-layer-shell
    wayland
    networkmanager
    upower
    libpulseaudio
    gnome-online-accounts
    libadwaita
    webkitgtk_6_0
    libsecret
    polkit
    gnome-desktop
    libsoup_3
    json-glib
    libpeas2
    vte-gtk4
    gtksourceview5
    poppler
    libdbusmenu
    at-spi2-core
    tinysparql
    libgudev
    libxcrypt
    pam
    hwdata
    qt6.qtbase
    glib
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    libgcrypt
    libgee
    libsodium
    libxcb
    pipewire
    cairo
    pango
    libpng
    libxkbcommon
    sdl2-compat
    libGL
    libGLU
    libx11
  ];

  patches = [
    greeterSessionWrapperPatch
    singularityDesktopRuntimePatch
    ../../patches/singularity-sensor-test-order.patch
  ];

  postPatch = ''
          # Upstream's bootstrap script downloads these files, which is not
          # permitted in the Nix build sandbox. Populate the same runtime
          # layout from fixed-output derivations instead.
          cp -r ${gestureRuntime}/. subprojects/singularity-gestures/runtime/

          # Fix hardcoded /usr/lib paths for polkit-agent-1
          substituteInPlace subprojects/singularity-shell/meson.build \
            --replace-fail \
              "cc.find_library('polkit-agent-1', dirs: ['/usr/lib/x86_64-linux-gnu', '/usr/lib'])" \
              "dependency('polkit-agent-1')"

          # Artist Packs are an apt/dpkg integration. Do not install their
          # privileged helpers or policy on NixOS; leaving the upstream paths
          # absent makes ArtistPackManager.is_available report false.
          substituteInPlace subprojects/singularity-shell/meson.build \
            --replace-fail \
              $'install_data(\'data/artist-packs/singularity-artist-pack-inventory\',\n  install_dir: \'/usr/local/bin\', install_mode: \'rwxr-xr-x\')\ninstall_data(\'data/artist-packs/singularity-artist-pack-install\',\n  install_dir: \'/usr/local/bin\', install_mode: \'rwxr-xr-x\')\ninstall_data(\'data/artist-packs/dev.sinty.desktop.artist-pack-install.policy\',\n  install_dir: get_option(\'datadir\') / \'polkit-1\' / \'actions\')' \
              '# Artist Pack helpers are unavailable on NixOS.'

          # The portal is a user service and must not depend on the ambient
          # session PATH for its color-picker backend. GCC 15's constant
          # merging at -O2 (injected by the Nix wrapper even for meson's
          # "plain" buildtype) corrupts long embedded absolute paths in the
          # generated C, so embed the binary beside the portal instead and
          # resolve it the same way the screenshot helpers are resolved.
          substituteInPlace subprojects/xdg-desktop-portal-singularity/src/screenshot.vala \
            --replace-fail \
              'string[] argv = {"hyprpicker"};' \
              'string[] argv = {resolve_companion_bin("hyprpicker")};'

          # singularity-git and singularity-edit are separate Nix outputs.
          # Resolve the editor through the application wrapper on PATH.
          substituteInPlace \
            subprojects/singularity-git/src/diff_window.vala \
            subprojects/singularity-git/src/window.vala \
            --replace-fail \
              '"/opt/local/bin/singularity-edit "' \
              '"singularity-edit "'

          # systemd.pc points at systemd's own immutable store output. User
          # units shipped by this package must instead live under this output.
          substituteInPlace subprojects/singularity-session/meson.build \
            --replace-fail \
              $'systemd_dep = dependency(\'systemd\', required: false)\nif systemd_dep.found()\n  systemd_user_unit_dir = systemd_dep.get_variable(pkgconfig: \'systemduserunitdir\')\nelse\n  systemd_user_unit_dir = get_option(\'prefix\') / \'lib\' / \'systemd\' / \'user\'\nendif' \
              "systemd_user_unit_dir = get_option('prefix') / 'lib' / 'systemd' / 'user'"

          # Keep the About page's library-version probe useful on ARM hosts.
          substituteInPlace subprojects/singularity-shell/src/core/system_components.vala \
            --replace-fail \
              '"/usr/lib/x86_64-linux-gnu", "/usr/lib64", "/usr/lib",' \
              '"/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu", "/usr/lib64", "/usr/lib",' \
            --replace-fail \
              '"/lib/x86_64-linux-gnu", "/opt/local/lib"' \
              '"/lib/x86_64-linux-gnu", "/lib/aarch64-linux-gnu", "/opt/local/lib"'

          # Skip singularity-demo (vetro GIR template issue with AppSidebar)
          substituteInPlace meson.build \
            --replace-fail \
              "subproject('singularity-demo')" \
              "# subproject('singularity-demo')"

          # singularity-store creates and installs its sidebar in Vala. The
          # template sidebar is unused, and Vetro emits it as GtkAppSidebar
          # without the libsingularity GIR metadata during the Nix build,
          # which breaks the template and leaves main_stack null at runtime.
          substituteInPlace subprojects/singularity-store/ui/main.vetro \
            --replace-fail \
              $'    AppSidebar(id: "sidebar_scroll", vexpand: true)\n\n' \
              ""

          # Don't try to install PAM file to /etc/pam.d (Nix sandbox)
          substituteInPlace subprojects/singularity-shell/src/lockscreen/meson.build \
            --replace-fail \
              "install_dir: '/etc/pam.d'," \
              "install_dir: get_option('prefix') / 'etc' / 'pam.d',"

          # labwc must use the XDG config search path. The shell writes its
          # live rc.xml, environment and themerc-override to ~/.config/labwc;
          # passing -C makes labwc ignore all of them.
          if grep -Fq -- '-C /usr/share/singularity/labwc' \
            subprojects/singularity-session/src/singularity-labwc-session; then
            substituteInPlace subprojects/singularity-session/src/singularity-labwc-session \
              --replace-fail \
                ' -C /usr/share/singularity/labwc' \
                ""
          fi
          if grep -Fq -- ' -C ' \
            subprojects/singularity-session/src/singularity-labwc-session; then
            echo "unexpected labwc -C config pin remains" >&2
            exit 1
          fi

          # Make labwc findable via PATH in the session script
          substituteInPlace subprojects/singularity-session/src/singularity-labwc-session \
            --replace-fail \
              '"$BIN/labwc"' \
              'labwc'
          substituteInPlace subprojects/singularity-session/src/singularity-labwc-session \
            --replace-fail \
              'export PATH="$BIN:$PATH"' \
              'export PATH="$BIN:''${PATH:+:$PATH}:${runtimeBinPath}"' \
            --replace-fail \
              'export LD_LIBRARY_PATH="$PREFIX/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
              'export LD_LIBRARY_PATH="$PREFIX/lib:${runtimeLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'

          substituteInPlace subprojects/singularity-session/src/singularity-desktop-session.in \
            --replace-fail \
              'export PATH="$BIN:$PATH"' \
              'export PATH="$BIN:''${PATH:+:$PATH}:${runtimeBinPath}"' \
            --replace-fail \
              'export LD_LIBRARY_PATH="$LIB''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
              'export LD_LIBRARY_PATH="$LIB:${runtimeLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
            --replace-fail \
              'export GSETTINGS_SCHEMA_DIR="$SHARE/glib-2.0/schemas"' \
              '# GSettings schemas are discovered through XDG_DATA_DIRS.'
          # Keep only XDG_DATA_DIRS in the activation environment. Session
          # source variants differ in whether GTK_USE_PORTAL and
          # QT_QPA_PLATFORM appear in this block.
          if grep -Fq -- '    GTK_USE_PORTAL QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME' \
            subprojects/singularity-session/src/singularity-desktop-session.in; then
            substituteInPlace subprojects/singularity-session/src/singularity-desktop-session.in \
              --replace-fail \
                $'    GTK_USE_PORTAL QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME \\\n    GSETTINGS_SCHEMA_DIR XDG_DATA_DIRS GI_TYPELIB_PATH PATH LD_LIBRARY_PATH \\' \
                $'    XDG_DATA_DIRS \\'
          elif grep -Fq -- '    GTK_USE_PORTAL QT_QPA_PLATFORMTHEME' \
            subprojects/singularity-session/src/singularity-desktop-session.in; then
            substituteInPlace subprojects/singularity-session/src/singularity-desktop-session.in \
              --replace-fail \
                $'    GTK_USE_PORTAL QT_QPA_PLATFORMTHEME \\\n    GSETTINGS_SCHEMA_DIR XDG_DATA_DIRS GI_TYPELIB_PATH PATH LD_LIBRARY_PATH \\' \
                $'    XDG_DATA_DIRS \\'
          elif grep -Fq -- '    QT_QPA_PLATFORMTHEME' \
            subprojects/singularity-session/src/singularity-desktop-session.in; then
            substituteInPlace subprojects/singularity-session/src/singularity-desktop-session.in \
              --replace-fail \
                $'    QT_QPA_PLATFORMTHEME \\\n    GSETTINGS_SCHEMA_DIR XDG_DATA_DIRS GI_TYPELIB_PATH PATH LD_LIBRARY_PATH \\' \
                $'    XDG_DATA_DIRS \\'
          else
            echo "unsupported singularity-desktop-session activation environment block" >&2
            exit 1
          fi

          # Some session sources also propagate wrapper-specific variables to
          # user services. Keep only the session identity and data directory
          # there.
          if grep -Fq -- 'systemctl --user set-environment' \
            subprojects/singularity-session/src/singularity-desktop-session.in; then
            substituteInPlace subprojects/singularity-session/src/singularity-desktop-session.in \
              --replace-fail \
                $'    QT_QPA_PLATFORMTHEME="$QT_QPA_PLATFORMTHEME" \\\n    XDG_DATA_DIRS="$XDG_DATA_DIRS" \\\n    GSETTINGS_SCHEMA_DIR="$GSETTINGS_SCHEMA_DIR" 2>/dev/null || true' \
                $'    XDG_DATA_DIRS="$XDG_DATA_DIRS" 2>/dev/null || true'

            grep -Fq -- '    XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP"' \
              subprojects/singularity-session/src/singularity-desktop-session.in
            grep -Fq -- '    XDG_DATA_DIRS="$XDG_DATA_DIRS"' \
              subprojects/singularity-session/src/singularity-desktop-session.in
            if grep -Fq -- '    QT_QPA_PLATFORMTHEME="$QT_QPA_PLATFORMTHEME"' \
              subprojects/singularity-session/src/singularity-desktop-session.in \
              || grep -Fq -- '    GSETTINGS_SCHEMA_DIR="$GSETTINGS_SCHEMA_DIR"' \
              subprojects/singularity-session/src/singularity-desktop-session.in; then
              echo "forbidden wrapper-specific variable remains in systemctl environment" >&2
              exit 1
            fi
          fi

          if ! grep -Eq -- 'systemctl --user( --no-block)? start singularity-session.target' \
            subprojects/singularity-session/src/singularity-desktop-session.in; then
            substituteInPlace subprojects/singularity-session/src/singularity-desktop-session.in \
              --replace-fail \
                '# Restart the portal so it picks up the live session environment, but do NOT' \
                $'systemctl --user start singularity-session.target 2>/dev/null || true\n\n# Restart the portal so it picks up the live session environment, but do NOT'
          fi
          grep -Eq -- 'systemctl --user( --no-block)? start singularity-session.target' \
            subprojects/singularity-session/src/singularity-desktop-session.in
          if grep -Fq -- 'trap "rm -f $_SPID" EXIT' \
            subprojects/singularity-session/src/singularity-desktop-session.in; then
            substituteInPlace subprojects/singularity-session/src/singularity-desktop-session.in \
              --replace-fail \
                'trap "rm -f $_SPID" EXIT' \
                "trap 'systemctl --user stop singularity-session.target 2>/dev/null || true; rm -f \"\$_SPID\"' EXIT"
          elif ! grep -Fq -- 'trap _session_cleanup EXIT' \
            subprojects/singularity-session/src/singularity-desktop-session.in \
            || ! grep -Eq -- 'systemctl --user( --no-block)? stop singularity-session.target' \
            subprojects/singularity-session/src/singularity-desktop-session.in; then
            echo "unsupported singularity-desktop-session cleanup block" >&2
            exit 1
          fi

          grep -Fq -- '    XDG_DATA_DIRS' \
            subprojects/singularity-session/src/singularity-desktop-session.in
          for forbidden in GSETTINGS_SCHEMA_DIR GI_TYPELIB_PATH LD_LIBRARY_PATH QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME; do
            if grep -Fq -- "    $forbidden" \
              subprojects/singularity-session/src/singularity-desktop-session.in; then
              echo "forbidden variable remains in dbus activation environment" >&2
              exit 1
            fi
          done

          substituteInPlace subprojects/singularity-greeter/src/greeter_main.c \
            --replace-fail \
              '"/opt/local/share/backgrounds/singularity/default.png",' \
              '"/opt/local/share/backgrounds/singularity/default.png", "'"$out"'/share/backgrounds/singularity/default.png",'

          # load_sessions(): let the NixOS module point the greeter at the
          # aggregated Wayland session desktop directory.
          substituteInPlace subprojects/singularity-greeter/src/greeter_main.c \
            --replace-fail \
              '    const char *dirs[] = {' \
              '    const char *env_dir = getenv("SINGULARITY_GREETER_SESSION_DIR");
    if (env_dir && !env_dir[0]) env_dir = NULL;
    const char *dirs[] = {'

          substituteInPlace subprojects/singularity-greeter/src/greeter_main.c \
            --replace-fail \
              '        "/opt/local/share/wayland-sessions",' \
              '        env_dir,
        "/opt/local/share/wayland-sessions",'

          # find_os_logo()
          substituteInPlace subprojects/singularity-greeter/src/greeter_main.c \
            --replace-fail \
              '"/opt/local/share/icons/hicolor/scalable/apps/%s.svg",' \
              '"/run/current-system/sw/share/icons/hicolor/scalable/apps/%s.svg", "/opt/local/share/icons/hicolor/scalable/apps/%s.svg",'

          substituteInPlace subprojects/singularity-splash/src/splash_main.c \
            --replace-fail \
              '"/opt/local/share/icons/hicolor/scalable/apps/%s.svg",' \
              '"/run/current-system/sw/share/icons/hicolor/scalable/apps/%s.svg", "/opt/local/share/icons/hicolor/scalable/apps/%s.svg",'

          # Custom greeter background from environment variables
          substituteInPlace subprojects/singularity-greeter/src/greeter_main.c \
            --replace-fail \
              'cairo_surface_t *bg = NULL;' \
              'cairo_surface_t *bg = NULL;
    const char *env_bg = getenv("SINGULARITY_GREETER_BACKGROUND");
    if (env_bg && env_bg[0]) {
        bg = loginui_load_wallpaper(env_bg, 960);
        if (bg) return bg;
    }'

          # Use Nix-provided data files instead of host absolute paths.
          substituteInPlace subprojects/libsingularity/src/system/locale_manager.vala \
            --replace-fail \
              '"/usr/share/i18n/SUPPORTED"' \
              '"${pkgs.glibcLocales}/share/i18n/SUPPORTED"'

          substituteInPlace subprojects/libsingularity/src/system/timezone_util.vala \
            --replace-fail \
              '"/usr/share/zoneinfo' \
              '"${pkgs.tzdata}/share/zoneinfo'

          substituteInPlace subprojects/libsingularity/src/system/input_source_util.vala \
            --replace-fail \
              'string[] paths = {' \
              'string[] paths = {
                "${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.lst",'

          substituteInPlace subprojects/singularity-shell/src/components/sidebar/widgets/developer_page.vala \
            --replace-fail \
              '"/usr/bin/tail"' \
              '"tail"'

          substituteInPlace subprojects/singularity-shell/src/components/run_dialog/run_dialog.vala \
            --replace-fail \
              '"/bin/bash"' \
              '"bash"'

          substituteInPlace subprojects/singularity-shell/src/components/run_dialog/run_dialog.vala \
            --replace-fail \
              '#!/bin/bash' \
              '#!${pkgs.bash}/bin/bash'

          # Meson drives these test scripts through bash, but the launchers
          # under test also exec them directly (as the fake compositor and
          # desktop binary). The build sandbox has no /usr/bin/env, so a
          # `#!/usr/bin/env bash` shebang makes every direct exec fail with
          # status 126. Resolve the interpreter up front.
          for test_script in subprojects/singularity-session/tests/*.sh; do
            substituteInPlace "$test_script" \
              --replace-fail \
                '#!/usr/bin/env bash' \
                '#!${pkgs.bash}/bin/bash'
          done
  '';

  # Upstream declares its unit/integration tests in Meson. Run them as part
  # of the package build so source updates cannot silently bypass the suite.
  doCheck = true;

  # The test suite runs in the build sandbox, which lacks the ambient desktop
  # environment: GIO content-type detection needs the shared MIME database,
  # GSettings tests need compiled schemas, and the prebuilt mediapipe runtime
  # dlopens the GLVND EGL/GLES libraries.
  nativeCheckInputs = with pkgs; [
    gsettings-desktop-schemas
    shared-mime-info
  ];

  preCheck = ''
    export GSETTINGS_SCHEMA_DIR="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
    export XDG_DATA_DIRS="${pkgs.shared-mime-info}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    export LD_LIBRARY_PATH="${pkgs.libglvnd}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # The prebuilt mediapipe runtime statically links tcmalloc, whose
    # initialization hard-requires a readable /sys/devices/system/cpu/possible
    # (TC_CHECK on NumCPUs). The Nix build sandbox mounts neither /sys nor
    # anything else at that path, so dlopen'ing the runtime aborts every test
    # that links it. Interpose openat to fall back to a stub topology — sized
    # from the sandbox CPU budget — when the real file cannot be opened. On
    # hosts where /sys is visible the shim is a passthrough.
    cat > tcmalloc-sys-shim.c <<'SHIM_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <sys/syscall.h>

static const char *target_path = "/sys/devices/system/cpu/possible";
static const char *stub_path = "tcmalloc-sys-cpu-possible";

static int (*real_openat)(int, const char *, int, ...);
static long (*real_syscall)(long, ...);

/* Serve the stub only when the real file is missing, so the shim is a
 * passthrough everywhere else. */
static int maybe_stub(int dirfd, const char *path, int flags, int mode, int rc) {
    if (rc >= 0 || errno != ENOENT || strcmp(path, target_path) != 0) return rc;
    return real_openat(dirfd, stub_path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...) {
    va_list ap;
    mode_t mode = 0;
    if (!real_openat) real_openat = dlsym(RTLD_NEXT, "openat");
    va_start(ap, flags);
    mode = va_arg(ap, int);
    va_end(ap);
    return maybe_stub(dirfd, path, flags, mode, real_openat(dirfd, path, flags, mode));
}

int open(const char *path, int flags, ...) {
    va_list ap;
    mode_t mode = 0;
    va_start(ap, flags);
    mode = va_arg(ap, int);
    va_end(ap);
    return maybe_stub(AT_FDCWD, path, flags, mode, openat(AT_FDCWD, path, flags, mode));
}

long syscall(long number, ...) {
    long args[6];
    va_list ap;
    int i;
    if (!real_syscall) real_syscall = dlsym(RTLD_NEXT, "syscall");
    va_start(ap, number);
    for (i = 0; i < 6; i++) args[i] = va_arg(ap, long);
    va_end(ap);
    if (number == SYS_openat && args[1] != 0) {
        return maybe_stub((int) args[0], (const char *) args[1], (int) args[2],
                          (int) args[3],
                          real_openat((int) args[0], (const char *) args[1],
                                      (int) args[2], (mode_t) args[3]));
    }
    return real_syscall(number, args[0], args[1], args[2], args[3], args[4], args[5]);
}
SHIM_EOF
    cc -shared -fPIC -o tcmalloc-sys-shim.so tcmalloc-sys-shim.c -ldl
    echo "0-$(($(nproc) - 1))" > tcmalloc-sys-cpu-possible
    export LD_PRELOAD="$PWD/tcmalloc-sys-shim.so''${LD_PRELOAD:+:$LD_PRELOAD}"
  '';

  # Split user-facing applications out of the desktop/session output so
  # NixOS can omit them from the system profile independently.
  postInstall = ''
    move_application_files() {
      app_id="$1"
      output_name="$2"
      output_path="''${!output_name}"

      while IFS= read -r -d "" app_path; do
        relative_path="''${app_path#$out/}"
        mkdir -p "$output_path/$(dirname "$relative_path")"
        mv "$app_path" "$output_path/$relative_path"
      done < <(
        find "$out" \( -type f -o -type l \) -print0 \
          | while IFS= read -r -d "" app_path; do
              base_name="$(basename "$app_path")"
              case "$base_name" in
                "singularity-$app_id"|"singularity-$app_id".*|"libsingularity-$app_id"*|"dev.sinty.$app_id"|"dev.sinty.$app_id".*)
                  printf '%s\0' "$app_path"
                  ;;
              esac
            done
      )
    }

    ${pkgs.lib.concatMapStringsSep "\n" (id: ''
      move_application_files "${id}" "${id}"
    '') applicationIds}

    # These icons belong to singularity-files, rather than the core desktop
    # output, even though their names do not carry the application id.
    files_icon_dir="$out/share/icons/hicolor/scalable/apps"
    files_icon_output="$files/share/icons/hicolor/scalable/apps"
    mkdir -p "$files_icon_output"
    for icon in ush-penguin.svg ush-penguin-symbolic.svg; do
      if [ -e "$files_icon_dir/$icon" ] || [ -L "$files_icon_dir/$icon" ]; then
        mv "$files_icon_dir/$icon" "$files_icon_output/"
      fi
    done

    # The editor's tree-sitter query files have language-based names,
    # so move their containing directory explicitly.
    if [ -d "$out/share/singularity-edit" ]; then
      mkdir -p "$edit/share"
      mv "$out/share/singularity-edit" "$edit/share/"
    fi
  '';

  postFixup = ''
    # Copy the Singularity labwc fork into the output so $BIN/labwc resolves at session startup.
    cp -r ${labwcPackage}/bin/labwc $out/bin/

    # Ship the color picker beside the portal: the portal resolves
    # hyprpicker as a sibling of /proc/self/exe (resolve_companion_bin),
    # keeping the color-picker subprocess an immutable provider rather
    # than an ambient-PATH lookup.
    cp ${pkgs.hyprpicker}/bin/hyprpicker $out/libexec/hyprpicker
    chmod +x $out/libexec/hyprpicker

    # Symlink polkit agent to bin/ so session script can find it
    ln -sf $out/libexec/singularity-polkit-agent $out/bin/
    ln -sf $out/libexec/singularity-polkit-auth-helper $out/bin/

    # Compile schemas and desktop databases independently in every
    # output so each selected application remains self-contained.
    for output_name in out ${pkgs.lib.concatStringsSep " " applicationIds}; do
      output_path="''${!output_name}"
      mkdir -p "$output_path/share/glib-2.0/schemas"
      schema_roots=$output_path/share/gsettings-schemas/*/glib-2.0/schemas
      for schema_src in $schema_roots; do
        [ -d "$schema_src" ] || continue
        for f in "$schema_src"/*.gschema.xml; do
          [ -e "$f" ] || continue
          ln -sf "$f" "$output_path/share/glib-2.0/schemas/"
        done
      done

      if find "$output_path/share/glib-2.0/schemas" -name '*.gschema.xml' -print -quit | grep -q .; then
        rm -f "$output_path/share/glib-2.0/schemas/gschemas.compiled"
        ${pkgs.glib.dev}/bin/glib-compile-schemas "$output_path/share/glib-2.0/schemas"
      fi

      if [ -d "$output_path/share/applications" ]; then
        rm -f "$output_path/share/applications/mimeinfo.cache"
        ${pkgs.desktop-file-utils}/bin/update-desktop-database "$output_path/share/applications"
      fi
    done

    if [ ! -e $out/share/glib-2.0/schemas/dev.sinty.desktop.gschema.xml ]; then
      echo "missing dev.sinty.desktop GSettings schema in $out/share/glib-2.0/schemas" >&2
      exit 1
    fi

    # Modify systemd user units to use $out paths instead of hardcoded /opt/...
    for systemd_user in $out/share/systemd/user $out/lib/systemd/user; do
      [ -d "$systemd_user" ] || continue

      if [ -f "$systemd_user/xdg-desktop-portal-singularity.service" ]; then
        sed -i \
          "s|^ExecStart=.*xdg-desktop-portal-singularity.*$|ExecStart=$out/libexec/xdg-desktop-portal-singularity|" \
          "$systemd_user/xdg-desktop-portal-singularity.service"
        grep -Fx "ExecStart=$out/libexec/xdg-desktop-portal-singularity" \
          "$systemd_user/xdg-desktop-portal-singularity.service" >/dev/null
      fi

      if [ -f "$systemd_user/singularity-polkit-agent.service" ]; then
        sed -i \
          "s|^ExecStart=.*singularity-polkit-agent.*$|ExecStart=$out/libexec/singularity-polkit-agent|" \
          "$systemd_user/singularity-polkit-agent.service"
        grep -Fx "ExecStart=$out/libexec/singularity-polkit-agent" \
          "$systemd_user/singularity-polkit-agent.service" >/dev/null
      fi
    done

    mkdir -p $out/share/dbus-1/services
    cat > $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.singularity.service << EOF
    [D-BUS Service]
    Name=org.freedesktop.impl.portal.desktop.singularity
    Exec=$out/libexec/xdg-desktop-portal-singularity
    SystemdService=xdg-desktop-portal-singularity.service
    EOF

    # Preferred portal routing for the "Singularity" desktop env
    # (XDG_CURRENT_DESKTOP=Singularity, set by the session script).
    # singularity.portal already advertises UseIn=Singularity, so
    # xdg-desktop-portal will pick it automatically; this file makes the
    # choice explicit and lets the Singularity impl be the first
    # responder with the GTK impl as a fallback for any interface
    # Singularity doesn't implement.
    mkdir -p $out/share/xdg-desktop-portal
    cat > $out/share/xdg-desktop-portal/singularity-portals.conf << EOF
    [preferred]
    default=singularity;gtk
    EOF

    # Register as a Wayland session for display managers
    mkdir -p $out/share/wayland-sessions
    cat > $out/share/wayland-sessions/singularity-desktop.desktop << EOF
    [Desktop Entry]
    Name=Singularity Desktop
    Comment=Singularity Desktop Environment
    Exec=$out/bin/singularity-labwc-session
    DesktopNames=Singularity
    Type=Application
    EOF
  '';

  meta = {
    description = "A Wayland desktop environment built on GTK4 and the labwc compositor";
    homepage = "https://github.com/singularityos-lab/singularity-desktop";
    license = nixpkgs.lib.licenses.gpl3Plus;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    maintainers = [ ];
    mainProgram = "singularity-desktop";
  };

  passthru = {
    providedSessions = [ "singularity-desktop" ];
    inherit labwcPackage;
  };
}
