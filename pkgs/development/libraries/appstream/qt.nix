{
  lib,
  stdenv,
  buildPackages,
  writeText,
  appstream,
  qtbase,
  qttools,
  nixosTests,
}:

# TODO: look into using the libraries from the regular appstream derivation as we keep duplicates here

stdenv.mkDerivation {
  pname = "appstream-qt";
  inherit (appstream) version src;

  outputs = [
    "out"
    "dev"
    "installedTests"
  ];

  buildInputs = appstream.buildInputs ++ [
    appstream
    qtbase
  ];

  nativeBuildInputs = appstream.nativeBuildInputs ++ [ qttools ];

  mesonFlags =
    appstream.mesonFlags
    ++ [
      (lib.mesonBool "qt" true)
    ]
    # A cross-built qtbase ships no moc/uic/rcc (it takes them from QT_HOST_PATH),
    # and meson's Qt module looks for them only in the host Qt's bindir/libexecdir
    # and on PATH, where the build platform's qtbase keeps them in libexec. Name
    # them in a cross file ("MOC sources specified and couldn't find uic-qt6"
    # otherwise).
    ++ lib.optionals (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) [
      "--cross-file=${writeText "appstream-qt-tools.ini" ''
        [binaries]
        moc = '${buildPackages.qt6.qtbase}/libexec/moc'
        uic = '${buildPackages.qt6.qtbase}/libexec/uic'
        rcc = '${buildPackages.qt6.qtbase}/libexec/rcc'
      ''}"
    ];

  patches = appstream.patches;

  dontWrapQtApps = true;

  # AppStreamQt tries to be relocatable, in hacky cmake ways that generally fail
  # horribly on NixOS. Just hardcode the paths.
  postFixup = ''
    sed -i "$dev/lib/cmake/AppStreamQt/AppStreamQtConfig.cmake" \
      -e "/INTERFACE_INCLUDE_DIRECTORIES/ s@\''${PACKAGE_PREFIX_DIR}@$dev@"
    sed -i "$dev/lib/cmake/AppStreamQt/AppStreamQtConfig.cmake" \
      -e "/IMPORTED_LOCATION/ s@\''${PACKAGE_PREFIX_DIR}@$out@"
  '';

  passthru = appstream.passthru // {
    tests = {
      installed-tests = nixosTests.installed-tests.appstream-qt;
    };
  };

  meta = appstream.meta // {
    description = "Software metadata handling library - Qt";
  };
}
