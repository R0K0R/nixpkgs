# Builds the Qt-patched GN meta-build tool from qtwebengine's src/3rdparty/gn/.
# The stock nixpkgs `gn` reports version "2341" (upstream GN revision), but
# qtwebengine's configure.cmake requires find_package(Gn <QT_REPO_MODULE_VERSION>
# EXACT) because the Qt-patched gn embeds the Qt version in its --version output
# (e.g. "6.140.0.qtwebengine.qt.io").  This derivation builds that patched gn so that
# IntraISACross (and real cross) qtwebengine builds can satisfy the version check.
{
  stdenv,
  ninja,
  python3,
  lib,
  qtwebengine,
}:
let
  # QT_REPO_MODULE_VERSION in .cmake.conf carries no pre-release suffix
  # ("6.140.0" for "6.140.0-rc"); FindGn compares against that.
  qtRepoModuleVersion = lib.head (lib.splitString "-" qtwebengine.version);
in
stdenv.mkDerivation {
  pname = "qt6-gn";
  # qtwebengine is released standalone (with its own version and a fetchzip
  # src) since Qt 6.12, so take both from the package itself.
  inherit (qtwebengine) version src;

  nativeBuildInputs = [
    ninja
    python3
  ];

  # gn build passes -Wno-format; nixpkgs hardening adds -Wformat-security which
  # requires -Wformat to be active — same issue as qtwebengine itself.
  hardeningDisable = [ "format" ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    python3 src/3rdparty/gn/build/gen.py \
        --no-last-commit-position \
        --no-static-libstdc++ \
        --out-path gn-build \
        --cc "$CC" \
        --cxx "$CXX" \
        --ld "$CXX" \
        --ar "$AR" \
        --allow-warnings \
        --platform linux \
        --qt-version "${qtRepoModuleVersion}.qtwebengine.qt.io"
    ninja -C gn-build gn
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp gn-build/gn $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "Qt-patched GN meta-build system for QtWebEngine cross-compilation";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ ];
  };
}
