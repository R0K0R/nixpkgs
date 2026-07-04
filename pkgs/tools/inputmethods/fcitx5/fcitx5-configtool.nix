{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  extra-cmake-modules,
  pkg-config,
  fcitx5,
  fcitx5-qt,
  qtbase,
  qtsvg,
  qtwayland,
  qtdeclarative,
  qtx11extras ? null,
  kitemviews,
  kwidgetsaddons,
  qtquickcontrols2 ? null,
  kcmutils,
  kcoreaddons,
  kdeclarative,
  kirigami ? null,
  kirigami2 ? null,
  isocodes,
  xkeyboard-config,
  libxkbfile,
  libplasma ? null,
  plasma-framework ? null,
  wrapQtAppsHook,
  kcmSupport ? true,
  pkgsBuildBuild,
}:

let
  # Reliable cross-or-pseudo-cross detection (see mk-kde-derivation.nix).
  isCrossOrPseudo =
    (stdenv.isIntraISACross or false) || !stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  # Several KDE framework cmake configs check `CMAKE_CROSSCOMPILING AND
  # KF6_HOST_TOOLING` to swap in BUILD-platform tool targets instead of running
  # a HOST-linked codegen binary that SIGILLs on the BUILD machine: KCMUtils'
  # kcmutils_add_plugin() (desktop-gen), KF6Config's kconfig_compiler, and
  # KF6Package (pulled in transitively via kdeclarative -> KF6Config and
  # libplasma -> KF6Package). mkKdeDerivation wires this automatically for
  # KDE-native packages via its own kf6HostTooling dir, now exposed as
  # mkKdeDerivation.kf6HostTooling precisely so non-mkKdeDerivation packages
  # like this one can reuse the single canonical, complete directory instead
  # of hand-copying a partial (and easily incomplete) subset per package.
  kf6HostTooling = pkgsBuildBuild.kdePackages.mkKdeDerivation.kf6HostTooling;
in

stdenv.mkDerivation rec {
  pname = "fcitx5-configtool";
  version = "5.1.13";

  src = fetchFromGitHub {
    owner = "fcitx";
    repo = pname;
    rev = version;
    hash = "sha256-STx2S5fuaZCsGoM8nsihYoW+C1GdkD3K7pT84aMRI9c=";
  };

  cmakeFlags = [
    (lib.cmakeBool "KDE_INSTALL_USE_QT_SYS_PATHS" true)
    (lib.cmakeBool "ENABLE_KCM" kcmSupport)
  ]
  ++ lib.optionals (isCrossOrPseudo && kcmSupport && lib.versions.major qtbase.version == "6") [
    "-DKF6_HOST_TOOLING=${kf6HostTooling}"
  ];

  nativeBuildInputs = [
    cmake
    extra-cmake-modules
    pkg-config
    wrapQtAppsHook
  ];

  buildInputs = [
    fcitx5
    fcitx5-qt
    qtbase
    qtsvg
    qtwayland
    kitemviews
    kwidgetsaddons
    isocodes
    xkeyboard-config
    libxkbfile
  ]
  ++ lib.optionals (lib.versions.major qtbase.version == "5") [
    qtx11extras
  ]
  ++ lib.optionals kcmSupport (
    [
      qtdeclarative
      kcoreaddons
      kdeclarative
    ]
    ++ lib.optionals (lib.versions.major qtbase.version == "5") [
      qtquickcontrols2
      plasma-framework
      kirigami2
    ]
    ++ lib.optionals (lib.versions.major qtbase.version == "6") [
      kcmutils
      libplasma
      kirigami
    ]
  );

  meta = {
    description = "Configuration Tool for Fcitx5";
    homepage = "https://github.com/fcitx/fcitx5-configtool";
    license = lib.licenses.gpl2Plus;
    maintainers = with lib.maintainers; [ poscat ];
    platforms = lib.platforms.linux;
    mainProgram = "fcitx5-config-qt";
  };
}
