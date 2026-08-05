{
  lib,
  stdenv,
  buildPackages,
  calf,
  cmake,
  deepfilternet,
  fetchFromGitHub,
  fftw,
  fftwFloat,
  glib,
  gsl,
  intltool,
  kdePackages,
  ladspa-header,
  libbs2b,
  libebur128,
  libmysofa,
  libsigcxx30,
  libsndfile,
  lilv,
  lsp-plugins,
  lv2,
  mda_lv2,
  ninja,
  nix-update-script,
  nlohmann_json,
  pipewire,
  pkg-config,
  qt6,
  rnnoise,
  rubberband,
  soundtouch,
  speexdsp,
  onetbb,
  webrtc-audio-processing,
  x42-plugins,
  zam-plugins,
  zita-convolver,
  wrapGAppsHook3,
}:

let
  inherit (qt6)
    qtbase
    qtgraphs
    wrapQtAppsHook
    ;
  inherit (kdePackages)
    breeze
    breeze-icons
    extra-cmake-modules
    kcolorscheme
    kconfigwidgets
    kiconthemes
    kirigami
    kirigami-addons
    qqc2-desktop-style
    ;
  speexdsp' = speexdsp.override { withFftw3 = false; };
  isCross = stdenv.hostPlatform != stdenv.buildPlatform;
  nativeKconfig = buildPackages.kdePackages.kconfig;
  nativeQtdeclarative = buildPackages.qt6.qtdeclarative;
  nativeQtquick3d = buildPackages.qt6.qtquick3d;
in

stdenv.mkDerivation (finalAttrs: {
  pname = "easyeffects";
  version = "8.2.7";

  src = fetchFromGitHub {
    owner = "wwmm";
    repo = "easyeffects";
    tag = "v${finalAttrs.version}";
    hash = "sha256-YYwVoqCRVAZVu8vCTN3ZSicy1Fzw3l+hQbooGAE/AEI=";
  };

  nativeBuildInputs = [
    cmake
    extra-cmake-modules
    intltool
    ninja
    pkg-config
    wrapGAppsHook3
    wrapQtAppsHook
  ]
  ++ lib.optionals isCross [
    nativeKconfig
    nativeQtdeclarative
    nativeQtquick3d
  ];

  dontWrapGApps = true;

  # qtgraphs' own cmake config (Qt6GraphsDependencies.cmake) internally
  # find_package()s Qt6Quick/Qt6Qml (from qtdeclarative) and Qt6Quick3D, but
  # only searches under CMAKE_CURRENT_LIST_DIR/.. (the HOST qtgraphs
  # prefix) -- neither qtdeclarative nor qtquick3d are easyeffects' own
  # direct inputs, so the generic addCMakeCrossHelperFlags hook (which only
  # reads cmake-cross-helper-flags off THIS derivation's own
  # buildInputs/nativeBuildInputs) never sees them. Point cmake at the
  # BUILD-platform *Tools_DIR configs directly.
  #
  # KF6Config_DIR: easyeffects isn't built with mkKdeDerivation, so KDE
  # Frameworks' KF6_HOST_TOOLING convention (which kf6HostTooling covers)
  # doesn't apply here; kconfigwidgets pulls in kconfig's HOST cmake config,
  # which points its own kconfig_add_kcfg_files macro at the HOST-tuned
  # kconfig_compiler_kf6, so cross-build must be told to use the
  # BUILD-platform one instead.
  cmakeFlags = lib.optionals isCross [
    "-DQt6QmlTools_DIR=${nativeQtdeclarative}/lib/cmake/Qt6QmlTools"
    "-DQt6QuickTools_DIR=${nativeQtdeclarative}/lib/cmake/Qt6QuickTools"
    "-DQt6Quick3DTools_DIR=${nativeQtquick3d}/lib/cmake/Qt6Quick3DTools"
    "-DKF6Config_DIR=${nativeKconfig.dev}/lib/cmake/KF6Config"
  ];

  buildInputs = [
    breeze
    breeze-icons
    deepfilternet
    fftw
    fftwFloat
    glib
    gsl
    kcolorscheme
    kconfigwidgets
    kiconthemes
    kirigami
    kirigami-addons
    ladspa-header
    qqc2-desktop-style
    libbs2b
    libebur128
    libmysofa
    libsigcxx30
    libsndfile
    lilv
    lv2
    nlohmann_json
    pipewire
    qtbase
    qtgraphs
    rnnoise
    rubberband
    soundtouch
    speexdsp'
    onetbb
    webrtc-audio-processing
    zita-convolver
  ]
  ++ lib.optionals stdenv.hostPlatform.isx86 [
    x42-plugins
  ];

  preFixup =
    let
      lv2Plugins = [
        calf # compressor exciter, bass enhancer and others
        lsp-plugins # delay, limiter, multiband compressor
        mda_lv2 # loudness
        zam-plugins # maximizer
      ]
      ++ lib.optionals stdenv.hostPlatform.isx86 [
        x42-plugins # autotune
      ];

      ladspaPlugins = [
        deepfilternet # deep noise remover
        rubberband # pitch shifting
      ];
    in
    ''
      qtWrapperArgs+=(
        "''${gappsWrapperArgs[@]}"
        --set LV2_PATH "${lib.makeSearchPath "lib/lv2" lv2Plugins}"
        --set LADSPA_PATH "${lib.makeSearchPath "lib/ladspa" ladspaPlugins}"
      )
    '';

  separateDebugInfo = true;

  passthru = {
    updateScript = nix-update-script { };
  };

  meta = {
    description = "Audio effects for PipeWire applications";
    homepage = "https://github.com/wwmm/easyeffects";
    changelog = "https://github.com/wwmm/easyeffects/blob/v${finalAttrs.version}/src/contents/docs/community/CHANGELOG.md";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [
      getchoo
      aleksana
      Gliczy
    ];
    mainProgram = "easyeffects";
    platforms = lib.platforms.linux;
  };
})
