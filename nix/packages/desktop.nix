{
  pkgs,
  nixpkgs,
  applicationIds,
  vetro,
  singularityLabwc,
  greeterSessionWrapperPatch,
}:
{
  pname ? "singularity-desktop",
  src,
}:
let
  runtimeBinPath = pkgs.lib.makeBinPath (
    with pkgs;
    [
      coreutils
      dbus
      procps
      systemd
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
  ];

  patches = [ greeterSessionWrapperPatch ];

  postPatch = ''
          # Fix hardcoded /usr/lib paths for polkit-agent-1
          substituteInPlace subprojects/singularity-shell/meson.build \
            --replace-fail \
              "cc.find_library('polkit-agent-1', dirs: ['/usr/lib/x86_64-linux-gnu', '/usr/lib'])" \
              "dependency('polkit-agent-1')"

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

          # Make labwc findable via PATH in the session script
          substituteInPlace subprojects/singularity-session/src/singularity-labwc-session \
            --replace-fail \
              '"$BIN/labwc"' \
              'labwc'

          substituteInPlace subprojects/singularity-session/src/singularity-labwc-session \
            --replace-fail \
              'export PATH="$BIN:$PATH"' \
              'export PATH="$BIN:${runtimeBinPath}''${PATH:+:$PATH}"' \
            --replace-fail \
              'export LD_LIBRARY_PATH="$PREFIX/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
              'export LD_LIBRARY_PATH="$PREFIX/lib:${runtimeLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'

          substituteInPlace subprojects/singularity-session/src/singularity-desktop-session \
            --replace-fail \
              'export PATH="$BIN:$PATH"' \
              'export PATH="$BIN:${runtimeBinPath}''${PATH:+:$PATH}"' \
            --replace-fail \
              'export LD_LIBRARY_PATH="$LIB''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
              'export LD_LIBRARY_PATH="$LIB:${runtimeLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
            --replace-fail \
              'export GSETTINGS_SCHEMA_DIR="$SHARE/glib-2.0/schemas"' \
              '# GSettings schemas are discovered through XDG_DATA_DIRS.' \
            --replace-fail \
              $'    QT_QPA_PLATFORMTHEME \\\n    GSETTINGS_SCHEMA_DIR XDG_DATA_DIRS GI_TYPELIB_PATH PATH LD_LIBRARY_PATH \\' \
              $'    XDG_DATA_DIRS \\' \
            --replace-fail \
              $'systemctl --user set-environment \\\n    XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP" \\\n    QT_QPA_PLATFORMTHEME="$QT_QPA_PLATFORMTHEME" \\\n    XDG_DATA_DIRS="$XDG_DATA_DIRS" \\\n    GSETTINGS_SCHEMA_DIR="$GSETTINGS_SCHEMA_DIR" 2>/dev/null || true' \
              $'systemctl --user set-environment \\\n    XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP" \\\n    XDG_DATA_DIRS="$XDG_DATA_DIRS" 2>/dev/null || true'

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

    # The editor's tree-sitter query files have language-based names,
    # so move their containing directory explicitly.
    if [ -d "$out/share/singularity-edit" ]; then
      mkdir -p "$edit/share"
      mv "$out/share/singularity-edit" "$edit/share/"
    fi
  '';

  postFixup = ''
    # Copy the Singularity labwc fork into the output so $BIN/labwc resolves at session startup.
    cp -r ${singularityLabwc}/bin/labwc $out/bin/

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
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };

  passthru.providedSessions = [ "singularity-desktop" ];
}
