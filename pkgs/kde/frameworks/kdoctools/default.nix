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
    (stdenv.isIntraISACross or false) || !stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  # docbookl10nhelper is internal (needs INSTALL_INTERNAL_TOOLS=ON) but
  # meinproc6 and checkXML6 are installed unconditionally, so a plain
  # BUILD-platform kdoctools build with that flag on gives us all three.
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

  # kdoctools compiles docbookl10nhelper, meinproc6, and checkXML6 with the
  # HOST compiler and immediately runs them as cmake POST_BUILD custom
  # commands to generate documentation. In a cross build, those HOST
  # binaries may not be executable on the build machine. kdoctools'
  # CMakeLists.txt already supports a cross-compiling mode: when
  # DOCBOOKL10NHELPER_EXECUTABLE/MEINPROC6_EXECUTABLE/CHECKXML6_EXECUTABLE
  # are set, it uses those imported targets instead of the tools it just
  # built for HOST.
  extraCmakeFlags = lib.optionals isCrossOrPseudo [
    "-DDOCBOOKL10NHELPER_EXECUTABLE=${nativeKdoctools}/bin/docbookl10nhelper"
    "-DMEINPROC6_EXECUTABLE=${nativeKdoctools}/bin/meinproc6"
    "-DCHECKXML6_EXECUTABLE=${nativeKdoctools}/bin/checkXML6"
  ];
}
