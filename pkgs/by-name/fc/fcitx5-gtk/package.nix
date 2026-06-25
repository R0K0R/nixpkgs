{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  kdePackages,
  fcitx5,
  gobject-introspection,
  glib,
  gtk2,
  gtk3,
  gtk4,
  fmt,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libxdmcp,
  libxkbcommon,
  libepoxy,
  dbus,
  at-spi2-core,
  libxtst,
  withGTK2 ? false,
}:

stdenv.mkDerivation rec {
  pname = "fcitx5-gtk";
  version = "5.1.6";

  src = fetchFromGitHub {
    owner = "fcitx";
    repo = pname;
    rev = version;
    hash = "sha256-4v3XWXXlTYOO2/SKnEBTr5WsGxqFLjsPgCE7goVrFGY=";
  };

  outputs = [
    "out"
    "dev"
  ];

  cmakeFlags = [
    "-DGOBJECT_INTROSPECTION_GIRDIR=share/gir-1.0"
    "-DGOBJECT_INTROSPECTION_TYPELIBDIR=lib/girepository-1.0"
  ]
  ++ lib.optional (!withGTK2) "-DENABLE_GTK2_IM_MODULE=off"
  # GIR scanner can't introspect HOST libraries in cross builds; cmake would
  # install FcitxG-1.0.gir into gobject-introspection's read-only store path.
  ++ lib.optional (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) "-DENABLE_GIR=OFF";

  buildInputs = [
    glib
    gtk3
    gtk4
    fmt
    fcitx5
    libuuid
    libselinux
    libsepol
    libthai
    libdatrie
    libxdmcp
    libxkbcommon
    libepoxy
    dbus
    at-spi2-core
    libxtst
  ]
  ++ lib.optional withGTK2 gtk2;

  nativeBuildInputs = [
    cmake
    pkg-config
    kdePackages.extra-cmake-modules
    gobject-introspection
  ];

  meta = {
    description = "Fcitx5 gtk im module and glib based dbus client library";
    homepage = "https://github.com/fcitx/fcitx5-gtk";
    license = lib.licenses.lgpl21Plus;
    maintainers = with lib.maintainers; [ poscat ];
    platforms = lib.platforms.linux;
  };
}
