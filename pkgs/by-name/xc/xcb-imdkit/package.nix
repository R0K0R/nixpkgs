{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  kdePackages,
  uthash,
  libxcb-util,
  libxcb-keysyms,
  xorgproto,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "xcb-imdkit";
  version = "1.0.9";

  src = fetchFromGitHub {
    owner = "fcitx";
    repo = "xcb-imdkit";
    rev = finalAttrs.version;
    hash = "sha256-QfuetGPY6u4OhFiE5/CoVEpdODWnd1PHWBtM3ymsZ98=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
  ];

  buildInputs = [
    kdePackages.extra-cmake-modules
    libxcb-util
    libxcb-keysyms
    # Both of these are header-only and are #included by the hostPlatform C
    # sources, so they are hostPlatform dependencies -- src/message.h opens with
    # #include <uthash.h>, and xorgproto supplies the X protocol headers reached
    # through the xcb ones. Upstream lists them in nativeBuildInputs, which puts
    # their -isystem into the buildPlatform compiler's flags only:
    #
    #   src/message.h:14:10: fatal error: uthash.h: No such file or directory
    #
    # Neither ships a binary or a build-time code generator, so nothing wants a
    # buildPlatform copy.
    uthash
    xorgproto
  ];

  meta = {
    description = "Input method development support for xcb";
    homepage = "https://github.com/fcitx/xcb-imdkit";
    license = lib.licenses.lgpl21Plus;
    maintainers = with lib.maintainers; [ poscat ];
    platforms = lib.platforms.linux;
  };
})
