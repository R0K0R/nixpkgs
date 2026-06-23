{
  lib,
  llvmPackages,
  python,
  shiboken6-generator,
  numpy,
  cmake,
  stdenv,
}:

let
  stdenv' = if stdenv.cc.isClang then stdenv else llvmPackages.stdenv;
in
stdenv'.mkDerivation (finalAttrs: {
  pname = "shiboken6";

  inherit (shiboken6-generator) version src;

  sourceRoot = "${finalAttrs.src.name}/sources/shiboken6";

  nativeBuildInputs = [
    cmake
    python.pkgs.ninja
    (python.pythonOnBuildForHost.withPackages (ps: [
      ps.packaging
      ps.setuptools
    ]))
  ]
  # In cross/pseudo-cross builds buildInputs are HOST packages and their bin/
  # dirs are not in PATH.  postInstall's `python3 setup.py egg_info` invokes
  # pyside6's setup_runner which calls options.find_qtpaths() → searches PATH
  # for qtpaths6.  Without this, the check fails with "No value provided to
  # --qtpaths".  qtpaths6 lives in qtbase/bin so we add qtbase to
  # nativeBuildInputs for cross builds to make it findable.
  ++ lib.optionals (stdenv.isPseudoCross or (!stdenv.buildPlatform.canExecute stdenv.hostPlatform)) [
    python.pkgs.qt6.qtbase
  ];

  propagatedNativeBuildInputs = [
    shiboken6-generator
  ];

  buildInputs = [
    python.pkgs.qt6.qtbase
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin python.pkgs.qt6.darwinVersionInputs;

  cmakeFlags = [
    "-DBUILD_TESTS=OFF"
    "-DNUMPY_INCLUDE_DIR=${numpy.coreIncludeDir}"
    "-Dis_pyside6_superproject_build=1"
    # shiboken6's cmake uses both find_package(Python) and ${Python3_EXECUTABLE}
    # in add_custom_command.  In cross mode cmake won't search PATH for either.
    # Set both variables explicitly so embedding_generator.py is invoked correctly
    # (otherwise the command becomes "-E script.py" → sh: -E: command not found).
    # cross-debug/41 (Python_EXECUTABLE) + cross-debug/42 (Python3_EXECUTABLE).
    "-DPython_EXECUTABLE=${python.pythonOnBuildForHost.interpreter}"
    "-DPython3_EXECUTABLE=${python.pythonOnBuildForHost.interpreter}"
    # When SHIBOKEN_IS_CROSS_BUILD=TRUE, libshiboken/CMakeLists.txt uses
    # ${QFP_PYTHON_HOST_PATH} (not Python_EXECUTABLE) for embedding_generator.py.
    # Without this, the add_custom_command becomes "-E script.py" → command not found.
    # cross-debug/43.
    "-DQFP_PYTHON_HOST_PATH=${python.pythonOnBuildForHost.interpreter}"
  ];

  # We intentionally use single quotes around `${BASH}` since it expands from a CMake
  # variable available in this file.
  postPatch = ''
    substituteInPlace cmake/ShibokenHelpers.cmake --replace-fail '#!/bin/bash' '#!''${BASH}'

    # raise ValueError('ZIP does not support timestamps before 1980')
    find \
      shibokenmodule/files.dir/shibokensupport/ \
      libshiboken/embed/signature_bootstrap.py \
      -exec touch -d "1980-01-01T00:00Z" {} \;
  '';

  postInstall = ''
    cd ../../..
    chmod +w .
    python3 setup.py egg_info --build-type=shiboken6
    cp -r shiboken6.egg-info $out/${python.sitePackages}/
  '';

  dontWrapQtApps = true;

  meta = {
    description = "Generator for the pyside6 Qt bindings - Python library";
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
