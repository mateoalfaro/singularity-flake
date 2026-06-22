{
  description = "Singularity Desktop — A Wayland desktop environment built on GTK4 and labwc";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    labwc-src = {
      url = "github:singularityos-lab/labwc";
      flake = false;
    };

    singularity-desktop-src = {
      url = "git+https://github.com/singularityos-lab/singularity-desktop.git?submodules=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, labwc-src, singularity-desktop-src }: let
    systems = [ "x86_64-linux" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    pkgsFor = system: nixpkgs.legacyPackages.${system};
  in {
    packages = forAllSystems (system: let
      pkgs = pkgsFor system;

      vetro = pkgs.buildGoModule rec {
        pname = "vetro";
        version = "0-unstable-2026-06-05";

        src = pkgs.fetchFromGitHub {
          owner = "singularityos-lab";
          repo = "vetro";
          rev = "0a7bd367676f67e1c15a304ba135fe6fecdbc604";
          hash = "sha256-BxAmyP6IqmqHEBmxKIRw0QMt14y/0CMOUab546xVYyQ=";
        };

        vendorHash = "sha256-BKIYil3eWmwqIUf/46LY426uBN7qrVaqWX3YvODj8gc=";

        # Names that already start with "Singularity" are fully-qualified
        # GObject type names; return them unchanged instead of prefixing "Gtk".
        postPatch = ''
          substituteInPlace internal/domain/vetro/utils.go \
            --replace-fail \
              $'\treturn gtkClassPrefix + name' \
              $'\tif strings.HasPrefix(name, "Singularity") {\n\t\treturn name\n\t}\n\treturn gtkClassPrefix + name'
        '';

        meta = {
          description = "Declarative GTK4 UI transpiler";
          homepage = "https://github.com/singularityos-lab/vetro";
          license = nixpkgs.lib.licenses.mit;
        };
      };

      singularityLabwc = pkgs.stdenv.mkDerivation {
        pname = "singularity-labwc";
        version = "0-unstable-2026-06-15";

        src = labwc-src;

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
      };

    in {
      default = pkgs.stdenv.mkDerivation {
        pname = "singularity-desktop";
        version = "0.1.0";

        src = singularity-desktop-src;

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
          libdecor
          labwc
          wayland
          wlroots
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
          libdisplay-info
          libliftoff
          mesa
          libdrm
          seatd
          systemd
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
          pixman
          libinput
          libxml2
          libpng
          librsvg
          libxkbcommon
        ];

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

          substituteInPlace subprojects/singularity-greeter/src/greeter_main.c \
            --replace-fail \
              '"/opt/local/share/backgrounds/singularity/default.png",' \
              '"/opt/local/share/backgrounds/singularity/default.png", "'"$out"'/share/backgrounds/singularity/default.png",'

          # load_sessions(): NixOS aggregates wayland-sessions in
          # /run/current-system/sw/share/wayland-sessions (populated by
          # services.displayManager.sessionPackages).
          substituteInPlace subprojects/singularity-greeter/src/greeter_main.c \
            --replace-fail \
              '"/opt/local/share/wayland-sessions",' \
              '"/run/current-system/sw/share/wayland-sessions", "/opt/local/share/wayland-sessions",'

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

        postFixup = ''
          # Copy the Singularity labwc fork into the output so $BIN/labwc resolves at session startup.
          cp -r ${singularityLabwc}/bin/labwc $out/bin/

          # Symlink polkit agent to bin/ so session script can find it
          ln -sf $out/libexec/singularity-polkit-agent $out/bin/
          ln -sf $out/libexec/singularity-polkit-auth-helper $out/bin/

          # Compile GSettings schemas (meson install put them in a non-standard location)
          mkdir -p $out/share/glib-2.0/schemas
          schema_src=$out/share/gsettings-schemas/singularity-desktop-0.1.0/glib-2.0/schemas
          if [ -d "$schema_src" ]; then
            for f in "$schema_src"/*.xml; do
              ln -sf "$f" $out/share/glib-2.0/schemas/
            done
            ${pkgs.glib.dev}/bin/glib-compile-schemas $out/share/glib-2.0/schemas
          fi

           # Modify systemd user units to use $out paths instead of hardcoded /opt/...

          systemd_user=$out/share/systemd/user
          substituteInPlace $systemd_user/xdg-desktop-portal-singularity.service \
            --replace-fail \
              "ExecStart=/bin/sh -c 'for d in /opt/local/bin /opt/bin /usr/local/bin %h/.local/singularity/bin /usr/bin; do if [ -x \"\$d/xdg-desktop-portal-singularity\" ]; then exec \"\$d/xdg-desktop-portal-singularity\"; fi; done; exit 1'" \
              "ExecStart=$out/libexec/xdg-desktop-portal-singularity"
          substituteInPlace $systemd_user/singularity-polkit-agent.service \
            --replace-fail \
              "ExecStart=/usr/libexec/singularity-polkit-agent" \
              "ExecStart=$out/libexec/singularity-polkit-agent"

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
          cat > $out/share/xdg-desktop-portal/portals.conf << EOF
          [preferred]
          default=singularity;gtk
          EOF

          # Build mimeinfo.cache so xdg-mime / GAppInfo resolve the bundled
          # .desktop files (e.g. singularity-edit launches for text/plain). On
          # NixOS this normally happens at the system-profile level, but
          # because the session puts $out/share FIRST in XDG_DATA_DIRS we want
          # a complete cache there too.
          if [ -d $out/share/applications ] && [ -x ${pkgs.desktop-file-utils}/bin/update-desktop-database ]; then
            ${pkgs.desktop-file-utils}/bin/update-desktop-database $out/share/applications
          fi

          # Register as a Wayland session for display managers
          mkdir -p $out/share/wayland-sessions
          cat > $out/share/wayland-sessions/singularity-desktop.desktop << EOF
          [Desktop Entry]
          Name=Singularity Desktop
          Comment=Singularity Desktop Environment
          Exec=$out/bin/singularity-labwc-session
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
      };
    });

    nixosModules.default = import ./nixos-module.nix self;
  };
}
