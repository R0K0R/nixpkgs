{
  lib,
  stdenv,
  cmake,
  cups,
  ninja,
  python,
  pythonImportsCheckHook,
  moveBuildTree,
  shiboken6,
  llvmPackages,
  symlinkJoin,
}:
let
  packages = with python.pkgs.qt6; [
    # required
    python.pkgs.ninja
    python.pkgs.packaging
    python.pkgs.setuptools
    qtbase

    # optional
    qt3d
    qtcharts
    qtconnectivity
    qtdatavis3d
    qtdeclarative
    qthttpserver
    qtmultimedia
    qtnetworkauth
    qtquick3d
    qtremoteobjects
    qtscxml
    qtsensors
    qtspeech
    qtsvg
    qtwebchannel
    qtwebsockets
    qtwebview
    qtpositioning
    qtlocation
    qtshadertools
    qtserialport
    qtserialbus
    qtgraphs
    qttools
  ];
  qt_linked = symlinkJoin {
    name = "qt_linked";
    paths = packages;
  };
in

stdenv.mkDerivation (finalAttrs: {
  pname = "pyside6";

  inherit (shiboken6) version src;

  sourceRoot = "${finalAttrs.src.name}/sources/pyside6";

  # Qt Designer plugin moved to a separate output to reduce closure size
  # for downstream things
  outputs = [
    "out"
    "devtools"
  ];

  # cmake/Macros/PySideModules.cmake supposes that all Qt frameworks on macOS
  # reside in the same directory as QtCore.framework, which is not true for Nix.
  # We therefore symLink all required and optional Qt modules in one directory tree ("qt_linked").
  postPatch = ''
    # Don't ignore optional Qt modules
    substituteInPlace cmake/PySideHelpers.cmake \
      --replace-fail \
        'string(FIND "''${_module_dir}" "''${_core_abs_dir}" found_basepath)' \
        'set (found_basepath 0)'

    # QWebEngineExtensionInfo/Manager are guarded by
    # QT_CONFIG(webengine_extensions), which is disabled in this qtwebengine
    # build (-1). shiboken6 finds no class definition for them and skips
    # generating the wrapper .cpp files, but cmake still tries to compile them
    # from two hardcoded places that don't know that:
    #   1. PySide6/QtWebEngineCore/CMakeLists.txt -- explicit source list
    #   2. PySide6/QtWebEngineCore/typesystem_webenginecore.xml -- shiboken6 typesystem
    # Patch both so cmake and shiboken6 agree on what actually gets generated.
    sed -i '/QWebEngineExtension/d' PySide6/QtWebEngineCore/typesystem_webenginecore.xml
    sed -i '/qwebengineextension/d' PySide6/QtWebEngineCore/CMakeLists.txt

    # In cross builds, the HOST qtbase has no Qt6CoreTools (a BUILD-only
    # package). Qt6CoreConfig.cmake requires it, but the mkspecs cmake probe
    # this invokes only reads feature flags -- it never actually needs the
    # tools themselves. QT_ALLOW_MISSING_TOOLS_PACKAGES suppresses that hard
    # failure.
    substituteInPlace ../../build_scripts/qtinfo.py \
      --replace-fail \
        'cmake_cache_args.extend(platform_cmake_options(as_tuple_list=True))' \
        'cmake_cache_args.extend(platform_cmake_options(as_tuple_list=True)); cmake_cache_args.append(("QT_ALLOW_MISSING_TOOLS_PACKAGES", "TRUE"))'
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace cmake/PySideHelpers.cmake \
      --replace-fail \
        "Designer" ""
  '';

  # "Couldn't find libclang.dylib You will likely need to add it manually to PATH to ensure the build succeeds."
  env = lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    LLVM_INSTALL_DIR = "${lib.getLib llvmPackages.libclang}/lib";
  };

  nativeBuildInputs = [
    cmake
    ninja
    python
    pythonImportsCheckHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ moveBuildTree ];

  buildInputs = (
    if stdenv.hostPlatform.isLinux then
      # qtwebengine fails under darwin
      # see https://github.com/NixOS/nixpkgs/pull/312987
      packages ++ [ python.pkgs.qt6.qtwebengine ]
    else
      python.pkgs.qt6.darwinVersionInputs
      ++ [
        qt_linked
        cups
      ]
  );

  propagatedBuildInputs = [ shiboken6 ];

  cmakeFlags = [
    "-DBUILD_TESTS=OFF"
    "-Dis_pyside6_superproject_build=1"
  ];

  dontWrapQtApps = true;

  postInstall = ''
    cd ../../..
    chmod +w .
    ${python.pythonOnBuildForHost.interpreter} setup.py egg_info --build-type=pyside6 \
      --qtpaths ${python.pkgs.qt6.qtbase}/bin/qtpaths6
    cp -r PySide6.egg-info $out/${python.sitePackages}/

    mkdir -p "$devtools"
    moveToOutput "${python.pkgs.qt6.qtbase.qtPluginPrefix}/designer" "$devtools"
  '';

  pythonImportsCheck = [ "PySide6" ];

  meta = {
    description = "Python bindings for Qt";
    license = with lib.licenses; [
      lgpl3Only
      gpl2Only
      gpl3Only
    ];
    homepage = "https://wiki.qt.io/Qt_for_Python";
    changelog = "https://code.qt.io/cgit/pyside/pyside-setup.git/tree/doc/changelogs/changes-${finalAttrs.version}?h=v${finalAttrs.version}";
    maintainers = [ ];
    platforms = lib.platforms.all;
  };
})
