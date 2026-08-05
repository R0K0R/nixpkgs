{
  stdenv,
  lib,
  fetchurl,
  cmake,
  qtbase,
  wrapQtAppsHook,
  buildPackages,
}:

let
  isQt6 = lib.versions.major qtbase.version == "6";
  cmakeName = if isQt6 then "KDSoap-qt6" else "KDSoap";
in
stdenv.mkDerivation rec {
  pname = "kdsoap";
  version = "2.2.0";

  src = fetchurl {
    url = "https://github.com/KDAB/KDSoap/releases/download/kdsoap-${version}/kdsoap-${version}.tar.gz";
    sha256 = "sha256-2e8RlIRCGXyfpEvW+63IQrcoCmDfxAV3r2b97WN681Y=";
  };

  outputs = [
    "out"
    "dev"
  ];

  nativeBuildInputs = [
    cmake
    wrapQtAppsHook
  ];

  buildInputs = [ qtbase ];

  cmakeFlags = [ (lib.cmakeBool "KDSoap_QT6" isQt6) ];

  postInstall = ''
    moveToOutput bin/kdwsdl2cpp* "$dev"
    substituteInPlace "$out/lib/cmake/${cmakeName}/KDSoapTargets-release.cmake" \
      --replace $out/bin $dev/bin
  ''
  # kdwsdl2cpp is KDSoap::kdwsdl2cpp, a build-time WSDL code generator every
  # consumer's own build invokes via this exported cmake target -- not a
  # runtime library. In a cross (or intra-ISA pseudo-cross) build, the HOST
  # kdwsdl2cpp this package just built may not be safely executable on the
  # actual build machine (wrong ISA outright, or -- confirmed via a real
  # SIGILL on yulee -- a different microarch tuning even when the ISA
  # matches). KDSoap's own cmake config has no cross-awareness of its own
  # (unlike KDE Frameworks' KF6_HOST_TOOLING convention, which this doesn't
  # implement), so point IMPORTED_LOCATION at the BUILD-platform kdwsdl2cpp
  # here, once, rather than leaving every individual consumer of KDSoap to
  # patch this same cmake file downstream (which is what happened before:
  # kdsoap-ws-discovery-client carried its own copy of this exact
  # substitution).
  + lib.optionalString (stdenv.hostPlatform != stdenv.buildPlatform) ''
    substituteInPlace "$out/lib/cmake/${cmakeName}/KDSoapTargets-release.cmake" \
      --replace-fail "$dev/bin/kdwsdl2cpp" "${buildPackages.kdePackages.kdsoap.dev}/bin/kdwsdl2cpp"
  '';

  meta = {
    description = "Qt-based client-side and server-side SOAP component";
    longDescription = ''
      KD Soap is a Qt-based client-side and server-side SOAP component.

      It can be used to create client applications for web services and also
      provides the means to create web services without the need for any further
      component such as a dedicated web server.
    '';
    license = with lib.licenses; [
      gpl2
      gpl3
      lgpl21
    ];
    maintainers = [ ];
  };
}
