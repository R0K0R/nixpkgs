{
  mkKdeDerivation,
  python3,
  libxml2,
  qtsvg,
  pkgsBuildBuild,
  stdenv,
  lib,
}:
# breeze-icons compiles helper tools (qrcAlias, generate-symbolic-dark) using
# the HOST compiler and then runs them immediately in the same cmake phase.
# In pseudo-cross the HOST compiler targets meteorlake (waitpkg), so the
# helpers crash on AMD builders.  The output (SVG icon theme + .rcc files) is
# architecture-independent, so use the BUILD-platform derivation directly.
# No circular evaluation: pkgsBuildBuild.kdePackages.breeze-icons evaluates
# with buildPlatform == hostPlatform and takes the mkKdeDerivation branch.
if (stdenv.isPseudoCross or false) || !stdenv.buildPlatform.canExecute stdenv.hostPlatform
then pkgsBuildBuild.kdePackages.breeze-icons
else
  mkKdeDerivation {
    pname = "breeze-icons";

    extraNativeBuildInputs = [
      (python3.withPackages (ps: [ ps.lxml ]))
      libxml2
    ];

    # This package contains an SVG icon theme and an API forcing its use
    extraPropagatedBuildInputs = [
      qtsvg
    ];

    # lots of icons, takes forever, does absolutely nothing
    dontStrip = true;

    # known upstream issue: https://invent.kde.org/frameworks/breeze-icons/-/commit/135e59fb4395c1779a52ab113cc70f7baa53fd5d
    dontCheckForBrokenSymlinks = true;
  }
