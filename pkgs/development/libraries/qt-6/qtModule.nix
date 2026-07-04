{
  lib,
  stdenv,
  pkgsBuildBuild,
  darwinVersionInputs,
  cmake,
  ninja,
  perl,
  moveBuildTree,
  srcs,
  patches ? [ ],
}:

args:

let
  inherit (args) pname;
  version = args.version or srcs.${pname}.version;
  src = args.src or srcs.${pname}.src;
  # Use explicit booleans rather than attrset comparison (which can
  # short-circuit on thunks in this context):
  #   isIntraISACross — same config string, different gcc.arch
  #   !canExecute     — real cross (aarch64 etc.; canExecute = false)
  isCrossOrPseudo =
    (stdenv.isIntraISACross or false) || !stdenv.buildPlatform.canExecute stdenv.hostPlatform;
in
stdenv.mkDerivation (
  args
  // {
    inherit pname version src;
    patches = args.patches or patches.${pname} or [ ];

    buildInputs =
      args.buildInputs or [ ] ++ lib.optionals stdenv.hostPlatform.isDarwin darwinVersionInputs;
    nativeBuildInputs =
      (args.nativeBuildInputs or [ ])
      ++ [
        cmake
        ninja
        perl
      ]
      ++ lib.optionals stdenv.hostPlatform.isDarwin [ moveBuildTree ];
    propagatedBuildInputs =
      (lib.warnIf (args ? qtInputs) "qt6.qtModule's qtInputs argument is deprecated" args.qtInputs or [ ])
      ++ (args.propagatedBuildInputs or [ ]);

    cmakeFlags = [
      # be more verbose
      "--log-level=STATUS"
      # don't leak OS version into the final output
      # https://bugreports.qt.io/browse/QTBUG-136060
      "-DCMAKE_SYSTEM_VERSION="
    ]
    # In cross builds, nixpkgs' cmake multi-output hook sets
    # CMAKE_INSTALL_LIBDIR to $out/lib (outputLib="out"), but getDev is
    # applied to host deps in cross derivations, so downstream builds only
    # have the dev output in their sandbox. Point LIBDIR at dev/lib so cmake
    # configs and libraries land somewhere downstream builds can see them,
    # matching non-cross output layout.
    # NOTE: Qt's own cmake infrastructure (QtBuildInternalsExtra.cmake)
    # force-sets INSTALL_LIBDIR="lib", so this flag has no actual effect in
    # practice currently; kept for documentation of intent and in case that
    # changes upstream.
    ++ lib.optionals isCrossOrPseudo [
      "-DCMAKE_INSTALL_LIBDIR=${placeholder "dev"}/lib"
      # Qt's cmake build system (qt_internal_check_host_path_set_for_cross_compiling
      # in QtBuildHelpers.cmake) requires QT_HOST_PATH whenever
      # CMAKE_CROSSCOMPILING=TRUE, which cmake sets here because the toolchain
      # targets a different gcc.arch. Point it at the BUILD-platform qtbase prefix.
      "-DQT_HOST_PATH=${pkgsBuildBuild.qt6.qtbase}"
      # Several Qt *Config.cmake files declare tool_deps on their respective
      # Tools packages (Qt6CoreConfig.cmake -> Qt6CoreTools for rcc/moc/uic;
      # Qt6QuickConfig.cmake/Qt6QmlConfig.cmake/Qt6ShaderToolsConfig.cmake ->
      # their own Tools packages for qmlcachegen/qmltc/qsb;
      # Qt6ScxmlConfig.cmake/Qt6RemoteObjectsConfig.cmake -> qscxmlc/repc;
      # Qt6Quick3DConfig.cmake -> balsam). Without pointing these at the
      # BUILD-platform Qt packages, cmake resolves each tool to a
      # HOST-platform binary, which may not be executable on the build
      # machine.
      "-DQt6CoreTools_DIR=${pkgsBuildBuild.qt6.qtbase}/lib/cmake/Qt6CoreTools"
      "-DQt6QuickTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QuickTools"
      "-DQt6QmlTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QmlTools"
      "-DQt6ShaderToolsTools_DIR=${pkgsBuildBuild.qt6.qtshadertools}/lib/cmake/Qt6ShaderToolsTools"
      "-DQt6ScxmlTools_DIR=${pkgsBuildBuild.qt6.qtscxml}/lib/cmake/Qt6ScxmlTools"
      "-DQt6RemoteObjectsTools_DIR=${pkgsBuildBuild.qt6.qtremoteobjects}/lib/cmake/Qt6RemoteObjectsTools"
      "-DQt6Quick3DTools_DIR=${pkgsBuildBuild.qt6.qtquick3d}/lib/cmake/Qt6Quick3DTools"
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      "-DQT_NO_XCODE_MIN_VERSION_CHECK=ON"
      # This is only used for the min version check, which we disabled above.
      # When this variable is not set, cmake tries to execute xcodebuild
      # to query the version.
      "-DQT_INTERNAL_XCODE_VERSION=0.1"
    ]
    ++ args.cmakeFlags or [ ];

    preConfigure = (args.preConfigure or "") + ''
      # In cross builds, nixpkgs' cmake env hook fires at targetOffset, so
      # NIXPKGS_CMAKE_PREFIX_PATH is never populated for HOST Qt packages and
      # cmake can't locate Qt6Config.cmake via CMAKE_PREFIX_PATH. Set it
      # explicitly from the Qt-specific env var that qmakePathHook/Qt's own
      # env hook DOES populate.
      if [[ -n "''${QT_ADDITIONAL_PACKAGES_PREFIX_PATH-}" ]]; then
        export CMAKE_PREFIX_PATH="''${QT_ADDITIONAL_PACKAGES_PREFIX_PATH}''${CMAKE_PREFIX_PATH:+:''${CMAKE_PREFIX_PATH}}"
      fi
    '';

    moveToDev = false;

    postInstall =
      (args.postInstall or "")
      + ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "$out" > "$dev/nix-support/qt-cmake-prefix"
        fi
      ''
      # Write cmake-cross-helper-flags so consumers with this module in
      # buildInputs get the BUILD-platform *Tools_DIR cmake flags
      # automatically via cmake's addCMakeCrossHelperFlags hook, instead of
      # every consumer needing to know and hand-write the flag itself. Each
      # module only writes the flag for its own Tools package; pname == "..."
      # is evaluated lazily, so pkgsBuildBuild.qt6.<other module> is never
      # forced except for the module it actually applies to.
      + lib.optionalString (isCrossOrPseudo && pname == "qtbase") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6CoreTools_DIR=${pkgsBuildBuild.qt6.qtbase}/lib/cmake/Qt6CoreTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (isCrossOrPseudo && pname == "qtdeclarative") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6QmlTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QmlTools" >> "$dev/nix-support/cmake-cross-helper-flags"
          echo "-DQt6QuickTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QuickTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (isCrossOrPseudo && pname == "qtshadertools") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6ShaderToolsTools_DIR=${pkgsBuildBuild.qt6.qtshadertools}/lib/cmake/Qt6ShaderToolsTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (isCrossOrPseudo && pname == "qtscxml") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6ScxmlTools_DIR=${pkgsBuildBuild.qt6.qtscxml}/lib/cmake/Qt6ScxmlTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (isCrossOrPseudo && pname == "qtremoteobjects") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6RemoteObjectsTools_DIR=${pkgsBuildBuild.qt6.qtremoteobjects}/lib/cmake/Qt6RemoteObjectsTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (isCrossOrPseudo && pname == "qtquick3d") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6Quick3DTools_DIR=${pkgsBuildBuild.qt6.qtquick3d}/lib/cmake/Qt6Quick3DTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      '';

    outputs =
      args.outputs or [
        "out"
        "dev"
      ];
    separateDebugInfo = args.separateDebugInfo or true;

    dontWrapQtApps = args.dontWrapQtApps or true;
  }
)
// {
  meta =

    let
      pos = builtins.unsafeGetAttrPos "pname" args;
    in
    {
      homepage = "https://www.qt.io/";
      description = "Cross-platform application framework for C++";
      license = with lib.licenses; [
        fdl13Plus
        gpl2Plus
        lgpl21Plus
        lgpl3Plus
      ];
      maintainers = with lib.maintainers; [
        nickcao
      ];
      platforms = lib.platforms.unix;
      position = "${pos.file}:${toString pos.line}";
    }
    // (args.meta or { });
}
