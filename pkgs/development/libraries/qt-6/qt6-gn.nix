# Builds the Qt-patched GN meta-build tool from qtwebengine's src/3rdparty/gn/.
# The stock nixpkgs `gn` reports version "2341" (upstream GN revision), but
# qtwebengine's configure.cmake requires find_package(Gn 6.11.0 EXACT) because
# the Qt-patched gn embeds the Qt version in its --version output
# ("6.11.0.qtwebengine.qt.io").  This derivation builds that patched gn so that
# pseudo-cross (and real cross) qtwebengine builds can satisfy the version check.
{
  stdenv,
  ninja,
  python3,
  lib,
  srcs,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "qt6-gn";
  inherit (srcs.qtwebengine) version src;
  sourceRoot = "qtwebengine-everywhere-src-${finalAttrs.version}";

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
        --qt-version "${finalAttrs.version}.qtwebengine.qt.io"
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
})
