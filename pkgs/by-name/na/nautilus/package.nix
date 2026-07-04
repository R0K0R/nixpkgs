{
  lib,
  stdenv,
  fetchurl,
  meson,
  ninja,
  pkg-config,
  gi-docgen,
  docbook-xsl-nons,
  gettext,
  blueprint-compiler,
  desktop-file-utils,
  wayland-scanner,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  libportal-gtk4,
  gnome,
  adwaita-icon-theme,
  gnome-autoar,
  glib-networking,
  icu,
  shared-mime-info,
  libnotify,
  libexif,
  libglycin,
  libglycin-gtk4,
  libjxl,
  libseccomp,
  librsvg,
  webp-pixbuf-loader,
  tinysparql,
  localsearch,
  gexiv2_0_16,
  libselinux,
  libcloudproviders,
  gdk-pixbuf,
  gnome-desktop,
  gst_all_1,
  gsettings-desktop-schemas,
  gnome-user-share,
  gobject-introspection,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "nautilus";
  version = "50.2.2";

  outputs = [
    "out"
    "dev"
    "devdoc"
  ];

  src = fetchurl {
    url = "mirror://gnome/sources/nautilus/${lib.versions.major finalAttrs.version}/nautilus-${finalAttrs.version}.tar.xz";
    hash = "sha256-4eKF7930LtMN2lsp9/jSQtq0vBQJqQVIY7NnutSzTVo=";
  };

  patches = [
    # Allow changing extension directory using environment variable.
    ./extension_dir.patch
  ];

  postPatch = ''
    # blueprint-compiler 0.20.4 SIGSEGVs in GLib type-system cleanup after
    # writing XML to a non-TTY fd (pipe/file), which is always the case in the
    # nix sandbox. strace confirms the XML is written correctly before the
    # crash. Pre-compile every .blp -> .ui here, ignoring the non-zero exit
    # (killed by SIGSEGV), then verify each output file is non-empty.
    # Patch the meson custom_target to cp the pre-compiled files instead of
    # re-invoking blueprint-compiler (which would SIGSEGV and abort the build).
    for blp in src/resources/ui/*.blp; do
      ui="''${blp%.blp}.ui"
      blueprint-compiler compile "$blp" > "$ui" || true
      [ -s "$ui" ] || { echo "blueprint-compiler produced empty $ui"; exit 1; }
    done
    substituteInPlace src/resources/meson.build \
      --replace-fail \
        "command: [blueprint_cmd, 'batch-compile', '--minify', '@OUTPUT@', '@CURRENT_SOURCE_DIR@', '@INPUT@']," \
        "command: ['sh', '-c', 'mkdir -p \"\$1/ui\" && cp \"\$2/ui/\"*.ui \"\$1/ui/\"', 'sh', '@OUTPUT@', '@CURRENT_SOURCE_DIR@'],"
  '';

  nativeBuildInputs = [
    blueprint-compiler
    desktop-file-utils
    gettext
    gobject-introspection
    meson
    ninja
    pkg-config
    gi-docgen
    docbook-xsl-nons
    wayland-scanner
    wrapGAppsHook4
  ];

  buildInputs = [
    gexiv2_0_16
    glib-networking
    icu
    gnome-desktop
    adwaita-icon-theme
    gsettings-desktop-schemas
    gnome-user-share
    gst_all_1.gst-plugins-base
    gtk4
    libadwaita
    libportal-gtk4
    libexif
    libnotify
    libseccomp
    libselinux
    gdk-pixbuf
    libcloudproviders
    shared-mime-info
    tinysparql
    localsearch
    gnome-autoar
    libglycin
    libglycin-gtk4
  ];

  propagatedBuildInputs = [
    gtk4
  ];

  mesonFlags = [
    "-Ddocs=true"
    "-Dtests=${if finalAttrs.finalPackage.doCheck then "all" else "none"}"
  ];

  preFixup = ''
    gappsWrapperArgs+=(
      # Thumbnailers
      --prefix XDG_DATA_DIRS : "${gdk-pixbuf}/share"
      --prefix XDG_DATA_DIRS : "${libjxl}/share"
      --prefix XDG_DATA_DIRS : "${librsvg}/share"
      --prefix XDG_DATA_DIRS : "${webp-pixbuf-loader}/share"
      --prefix XDG_DATA_DIRS : "${shared-mime-info}/share"
    )
  '';

  postFixup = ''
    # Cannot be in postInstall, otherwise _multioutDocs hook in preFixup will move right back.
    moveToOutput "share/doc" "$devdoc"
  '';

  passthru = {
    updateScript = gnome.updateScript {
      packageName = "nautilus";
    };
  };

  meta = {
    description = "File manager for GNOME";
    homepage = "https://apps.gnome.org/Nautilus/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    teams = [ lib.teams.gnome ];
    mainProgram = "nautilus";
  };
})
