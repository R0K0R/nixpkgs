self:
{
  lib,
  stdenv,
  makeSetupHook,
  cmake,
  ninja,
  qt6,
  python3,
  python3Packages,
  pkgsBuildBuild,
  jq,
}:
let
  # Reliable cross-or-intra-ISA-cross detection: attrset comparison
  # (hostPlatform != buildPlatform) can short-circuit on thunks in some
  # contexts, so use the explicit predicate plus a canExecute fallback for
  # true cross instead.
  isCrossOrPseudo =
    (stdenv.isIntraISACross or false) || !stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  dependencies = (lib.importJSON ../generated/dependencies.json).dependencies;
  projectInfo = lib.importJSON ../generated/projects.json;

  licenseInfo = lib.importJSON ../generated/licenses.json;
  licensesBySpdxId =
    (lib.mapAttrs' (_: v: {
      name = v.spdxId or "unknown";
      value = v;
    }) lib.licenses)
    // {
      # https://community.kde.org/Policies/Licensing_Policy
      "LicenseRef-KDE-Accepted-GPL" = lib.licenses.gpl3Plus;
      "LicenseRef-KFQF-Accepted-GPL" = lib.licenses.gpl3Plus;
      "LicenseRef-KDE-Accepted-LGPL" = lib.licenses.lgpl3Plus;

      # https://sjfonts.sourceforge.net/
      "LicenseRef-SJFonts" = lib.licenses.gpl2Plus;

      # https://invent.kde.org/education/kiten/-/blob/master/LICENSES/LicenseRef-EDRDG.txt
      "LicenseRef-EDRDG" = lib.licenses.cc-by-sa-30;

      # https://invent.kde.org/kdevelop/kdevelop/-/blob/master/LICENSES/LicenseRef-MIT-KDevelop-Ideal.txt
      "LicenseRef-MIT-KDevelop-Ideal" = lib.licenses.mit;

      "FSFAP" = {
        spdxId = "FSFAP";
        fullName = "FSF All Permissive License";
      };

      "FSFULLR" = {
        spdxId = "FSFULLR";
        fullName = "FSF Unlimited License (with License Retention)";
      };

      "W3C-20150513" = {
        spdxId = "W3C-20150513";
        fullName = "W3C Software Notice and Document License (2015-05-13)";
      };

      "LGPL" = lib.licenses.lgpl2Plus;

      # Technically not exact
      "bzip2-1.0.6" = lib.licenses.bsdOriginal;

      # FIXME: typo lol
      "ICS" = lib.licenses.isc;
      "BSD-2-Clauses" = lib.licenses.bsd2;
      "BSD-3-clause" = lib.licenses.bsd3;
      "BSD-3-Clauses" = lib.licenses.bsd3;

      # These are only relevant to Qt commercial users
      "Qt-Commercial-exception-1.0" = null;
      "LicenseRef-Qt-Commercial" = null;
      "LicenseRef-Qt-Commercial-exception-1.0" = null;

      # FIXME: ???
      "Qt-GPL-exception-1.0" = null;
      "LicenseRef-Qt-LGPL-exception-1.0" = null;
      "Qt-LGPL-exception-1.1" = null;
      "LicenseRef-Qt-exception" = null;
      "GCC-exception-3.1" = null;
      "Bison-exception-2.2" = null;
      "Font-exception-2.0" = null;
      None = null;
    };

  moveOutputsHook = makeSetupHook {
    name = "kf6-move-outputs-hook";
    meta.license = lib.licenses.mit;
  } ./move-outputs-hook.sh;

  qmllintHook = makeSetupHook {
    name = "qmllint-validate-hook";
    substitutions = {
      qmllint = "${qt6.qtdeclarative}/bin/qmllint";
      jq = lib.getExe jq;
    };
    meta.license = lib.licenses.mit;
  } ./qmllint-hook.sh;

  # Unified BUILD-platform KDE cmake tool directory. cmake's find_file()
  # searches KF6_HOST_TOOLING for <Pkg>/<Pkg>ToolsTargets.cmake (one subdir
  # per KDE framework that ships cross-build tools). Each symlink points at
  # the BUILD-platform cmake install, whose targets already reference BUILD
  # binaries, so no path patching is needed.
  kf6HostTooling = pkgsBuildBuild.runCommand "kf6-host-tooling" { } ''
    mkdir -p "$out"
    ln -s "${pkgsBuildBuild.kdePackages.kdoctools.dev}/lib/cmake/KF6DocTools"   "$out/KF6DocTools"
    ln -s "${pkgsBuildBuild.kdePackages.kconfig.dev}/lib/cmake/KF6Config"      "$out/KF6Config"
    ln -s "${pkgsBuildBuild.kdePackages.kpackage.dev}/lib/cmake/KF6Package"    "$out/KF6Package"
    ln -s "${pkgsBuildBuild.kdePackages.kcmutils.dev}/lib/cmake/KF6KCMUtils"   "$out/KF6KCMUtils"
  '';
in
{
  # Exposed so non-mkKdeDerivation packages needing the same
  # CMAKE_CROSSCOMPILING/KF6_HOST_TOOLING pattern can reuse this single
  # canonical, complete directory instead of hand-assembling a partial subset
  # themselves.
  inherit kf6HostTooling;

  # Named _mkKdeDerivation, not `self` -- `self` here would shadow this file's
  # own top-level `self:` (the KDE package set), which every `self.sources.*` /
  # `self.${dep}` reference below relies on.
  __functor = _mkKdeDerivation: {
  pname,
  version ? self.sources.${pname}.version,
  src ? self.sources.${pname},
  extraBuildInputs ? [ ],
  extraNativeBuildInputs ? [ ],
  extraPropagatedBuildInputs ? [ ],
  extraCmakeFlags ? [ ],
  excludeDependencies ? [ ],
  hasPythonBindings ? false,
  ...
}@args:
let
  depNames = dependencies.${pname} or [ ];
  filteredDepNames = builtins.filter (dep: !(builtins.elem dep excludeDependencies)) depNames;

  # FIXME(later): this is wrong for cross, some of these things really need to go into nativeBuildInputs,
  # but cross is currently very broken anyway, so we can figure this out later.
  deps = map (dep: self.${dep}) filteredDepNames;

  traceDuplicateDeps =
    attrName: attrValue:
    let
      pretty = lib.generators.toPretty { };
      duplicates = builtins.filter (
        dep: dep != null && builtins.elem (lib.getName dep) filteredDepNames
      ) attrValue;
    in
    if duplicates != [ ] then
      lib.warn "Duplicate dependencies in ${attrName} of package ${pname}: ${pretty duplicates}"
    else
      lib.id;

  traceAllDuplicateDeps = lib.flip lib.pipe [
    (traceDuplicateDeps "extraBuildInputs" extraBuildInputs)
    (traceDuplicateDeps "extraPropagatedBuildInputs" extraPropagatedBuildInputs)
  ];

  defaultArgs = {
    inherit version src;

    outputs = [
      "out"
      "dev"
      "devtools"
    ]
    ++ lib.optionals hasPythonBindings [ "python" ];

    nativeBuildInputs = [
      cmake
      ninja
      qt6.wrapQtAppsHook
      moveOutputsHook
      qmllintHook
    ]
    ++ lib.optionals hasPythonBindings [
      python3Packages.shiboken6
      (python3.withPackages (ps: [
        ps.build
        ps.setuptools
      ]))
    ]
    ++ extraNativeBuildInputs;

    buildInputs = [
      qt6.qtbase
    ]
    ++ lib.optionals hasPythonBindings [
      python3Packages.pyside6
    ]
    ++ extraBuildInputs;

    # FIXME: figure out what to propagate here
    propagatedBuildInputs = deps ++ extraPropagatedBuildInputs;
    strictDeps = true;

    cmakeFlags = [ "-DQT_MAJOR_VERSION=6" ]
      # Qt's cmake modules locate their *Tools packages (rcc, moc, qmlcachegen,
      # qsb, etc.) via CMAKE_PREFIX_PATH, which in a cross build only contains
      # HOST Qt paths. HOST Qt's *Tools packages contain HOST-architecture
      # binaries, which may not be executable on the build machine (e.g. a
      # different microarch tuning, or a genuinely different ISA). Point
      # cmake explicitly at the BUILD-platform qt6 *Tools dirs instead, so
      # cmake invokes tools it can actually run.
      ++ lib.optionals isCrossOrPseudo [
        "-DQt6CoreTools_DIR=${pkgsBuildBuild.qt6.qtbase}/lib/cmake/Qt6CoreTools"
        "-DQt6QmlTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QmlTools"
        "-DQt6QuickTools_DIR=${pkgsBuildBuild.qt6.qtdeclarative}/lib/cmake/Qt6QuickTools"
        "-DQt6ShaderToolsTools_DIR=${pkgsBuildBuild.qt6.qtshadertools}/lib/cmake/Qt6ShaderToolsTools"
        "-DQt6ScxmlTools_DIR=${pkgsBuildBuild.qt6.qtscxml}/lib/cmake/Qt6ScxmlTools"
        "-DQt6RemoteObjectsTools_DIR=${pkgsBuildBuild.qt6.qtremoteobjects}/lib/cmake/Qt6RemoteObjectsTools"
        "-DQt6Quick3DTools_DIR=${pkgsBuildBuild.qt6.qtquick3d}/lib/cmake/Qt6Quick3DTools"
        # KDE framework cmake configs check `CMAKE_CROSSCOMPILING AND
        # KF6_HOST_TOOLING` and, when true, do find_file(<Pkg>/<Pkg>ToolsTargets.cmake
        # PATHS ${KF6_HOST_TOOLING}) to load BUILD-platform tool targets instead
        # of running HOST binaries that may not be executable on the build
        # machine. kf6HostTooling aggregates every KDE framework's
        # BUILD-platform cmake tool subdir into one tree, so this single value
        # satisfies every framework that uses the pattern.
        "-DCMAKE_CROSSCOMPILING=TRUE"
        "-DKF6_HOST_TOOLING=${kf6HostTooling}"
      ]
      ++ extraCmakeFlags;

    doInstallCheck = true;

    separateDebugInfo = true;

    env.LANG = "C.UTF-8";
  };

  cleanArgs = removeAttrs args [
    "extraBuildInputs"
    "extraNativeBuildInputs"
    "extraPropagatedBuildInputs"
    "extraCmakeFlags"
    "excludeDependencies"
    "hasPythonBindings"
    "meta"
  ];

  meta = {
    description = projectInfo.${pname}.description;
    homepage = "https://invent.kde.org/${projectInfo.${pname}.repo_path}";
    donationPage = "https://kde.org/donate/";
    license = lib.filter (l: l != null) (map (l: licensesBySpdxId.${l}) licenseInfo.${pname});
    teams = [ lib.teams.qt-kde ];
    # Platforms are currently limited to what upstream tests in CI, but can be extended if there's interest.
    platforms = lib.platforms.linux ++ lib.platforms.freebsd;
  }
  // (args.meta or { });

  pos = builtins.unsafeGetAttrPos "pname" args;
in
traceAllDuplicateDeps (stdenv.mkDerivation (defaultArgs // cleanArgs // { inherit meta pos; }));
}
