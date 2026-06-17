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
    # In cross builds nixpkgs's cmake multi-output hook sets CMAKE_INSTALL_LIBDIR
    # to $out/lib (outputLib="out"), but getDev is applied to host deps in cross
    # drvs so downstream builds only have the dev output in their sandbox.
    # Setting LIBDIR to dev/lib puts cmake configs + libs in dev where they are
    # accessible, matching how non-cross outputs lay out.
    # NOTE: this flag is actually overridden by Qt's own cmake infrastructure
    # (QtBuildInternalsExtra.cmake FORCE-sets INSTALL_LIBDIR="lib") and has no
    # effect in practice, but is kept harmlessly for documentation purposes.
    ++ lib.optionals (stdenv.buildPlatform != stdenv.hostPlatform) [
      "-DCMAKE_INSTALL_LIBDIR=${placeholder "dev"}/lib"
      # Qt6CoreConfig.cmake declares a tool_dep on Qt6CoreTools (rcc, moc, uic).
      # Without this, cmake resolves Qt6::rcc to the HOST platform rcc binary,
      # which crashes on the build machine when HOST uses an ISA extension (e.g.
      # waitpkg on meteorlake) not supported by the build machine (e.g. AMD znver).
      # Point directly to BUILD platform qtbase so cmake finds the native rcc/moc/uic.
      "-DQt6CoreTools_DIR=${pkgsBuildBuild.qt6.qtbase}/lib/cmake/Qt6CoreTools"
      # Qt6QuickConfig.cmake, Qt6QmlConfig.cmake, and Qt6ShaderToolsConfig.cmake each
      # declare tool_deps on their respective Tools packages. These tool cmake configs
      # only exist in the BUILD platform Qt packages (they define native executables
      # like qmlcachegen, qmltc, qsb). Downstream HOST packages need to find them so
      # Qt::Quick / Qt::Qml / Qt::ShaderTools are considered FOUND.
      "-DQt6QuickTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QuickTools"
      "-DQt6QmlTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QmlTools"
      "-DQt6ShaderToolsTools_DIR=${pkgsBuildBuild.qt6.qtshadertools}/lib/cmake/Qt6ShaderToolsTools"
      # Qt6ScxmlConfig.cmake and Qt6RemoteObjectsConfig.cmake also declare tool
      # dependencies (qscxmlc and repc) following the same pattern.
      "-DQt6ScxmlTools_DIR=${pkgsBuildBuild.qt6.qtscxml}/lib/cmake/Qt6ScxmlTools"
      "-DQt6RemoteObjectsTools_DIR=${pkgsBuildBuild.qt6.qtremoteobjects}/lib/cmake/Qt6RemoteObjectsTools"
      # Qt6Quick3DConfig.cmake declares a tool_dep on Qt6Quick3DTools (balsam).
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
      # In pseudo-cross builds the cmake hook fires at targetOffset=1 (not hostOffset=0),
      # so NIXPKGS_CMAKE_PREFIX_PATH is never populated for host Qt packages and cmake
      # cannot locate Qt6Config.cmake via CMAKE_PREFIX_PATH. Set it explicitly from the
      # Qt-specific env var that IS populated by addQtModulePrefix.
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
      # F12: Write cmake-cross-helper-flags to $dev/nix-support/ so that consumers
      # with this module in buildInputs get the BUILD-platform *Tools_DIR cmake vars
      # automatically via the addCMakeCrossHelperFlags hook in cmake/setup-hook.sh.
      # Each module only writes flags for its own *Tools package. The Nix-level
      # pname == "..." conditions are evaluated lazily at eval time, so accessing
      # pkgsBuildBuild.qt6.qtscxml here is only evaluated when pname IS qtscxml.
      + lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform && pname == "qtbase") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6CoreTools_DIR=${pkgsBuildBuild.qt6.qtbase}/lib/cmake/Qt6CoreTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform && pname == "qtdeclarative") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6QmlTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QmlTools" >> "$dev/nix-support/cmake-cross-helper-flags"
          echo "-DQt6QuickTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QuickTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform && pname == "qtshadertools") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6ShaderToolsTools_DIR=${pkgsBuildBuild.qt6.qtshadertools}/lib/cmake/Qt6ShaderToolsTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform && pname == "qtscxml") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6ScxmlTools_DIR=${pkgsBuildBuild.qt6.qtscxml}/lib/cmake/Qt6ScxmlTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform && pname == "qtremoteobjects") ''
        if [[ -n "''${dev:-}" ]]; then
          mkdir -p "$dev/nix-support"
          echo "-DQt6RemoteObjectsTools_DIR=${pkgsBuildBuild.qt6.qtremoteobjects}/lib/cmake/Qt6RemoteObjectsTools" >> "$dev/nix-support/cmake-cross-helper-flags"
        fi
      ''
      + lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform && pname == "qtquick3d") ''
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
