{
  mkKdeDerivation,
  docbook_xml_dtd_45,
  docbook-xsl-nons,
  perl,
  perlPackages,
  libxml2,
  pkgsBuildBuild,
  stdenv,
  lib,
}:
let
  isCrossOrPseudo =
    (stdenv.isPseudoCross or false) || !stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  # docbookl10nhelper is internal (INSTALL_INTERNAL_TOOLS=ON needed) but
  # meinproc6 and checkXML6 are unconditionally installed.
  nativeKdoctools =
    if isCrossOrPseudo
    then
      pkgsBuildBuild.kdePackages.kdoctools.overrideAttrs (old: {
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DINSTALL_INTERNAL_TOOLS=ON" ];
      })
    else
      null;
in
mkKdeDerivation {
  pname = "kdoctools";

  # Perl could be used both at build time and at runtime.
  extraNativeBuildInputs = [
    perl
    perlPackages.URI
    libxml2
  ] ++ lib.optional isCrossOrPseudo nativeKdoctools;

  extraBuildInputs = [
    docbook_xml_dtd_45
    docbook-xsl-nons
  ];

  extraPropagatedBuildInputs = [
    perl
    perlPackages.URI
  ];

  # In cross/pseudo-cross builds kdoctools compiles docbookl10nhelper, meinproc6,
  # and checkXML6 for HOST (meteorlake) then immediately runs them as cmake
  # POST_BUILD custom commands.  HOST binaries crash on AMD builders.
  # kdoctools CMakeLists.txt supports CMAKE_CROSSCOMPILING mode: when
  # DOCBOOKL10NHELPER_EXECUTABLE/MEINPROC6_EXECUTABLE/CHECKXML6_EXECUTABLE are
  # set it uses those imported targets instead of the just-built HOST binaries.
  extraCmakeFlags = lib.optionals isCrossOrPseudo [
    "-DDOCBOOKL10NHELPER_EXECUTABLE=${nativeKdoctools}/bin/docbookl10nhelper"
    "-DMEINPROC6_EXECUTABLE=${nativeKdoctools}/bin/meinproc6"
    "-DCHECKXML6_EXECUTABLE=${nativeKdoctools}/bin/checkXML6"
  ];
}
