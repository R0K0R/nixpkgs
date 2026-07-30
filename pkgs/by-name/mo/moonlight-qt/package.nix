{
  stdenv,
  lib,
  fetchFromGitHub,
  fetchpatch,
  qt6,
  pkg-config,
  vulkan-headers,
  SDL2,
  SDL2_ttf,
  ffmpeg,
  libopus,
  libplacebo,
  openssl,
  alsa-lib,
  libpulseaudio,
  libva,
  libvdpau,
  libxkbcommon,
  wayland,
  libdrm,
  libGL,
  nix-update-script,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "moonlight-qt";
  version = "6.1.0";

  src = fetchFromGitHub {
    owner = "moonlight-stream";
    repo = "moonlight-qt";
    tag = "v${finalAttrs.version}";
    hash = "sha256-rWVNpfRDLrWsqELPFquA6rW6/AfWV+6DNLUCPqIhle0=";
    fetchSubmodules = true;
  };

  patches = [
    # Fix build for Xcode < 14
    (fetchpatch {
      url = "https://github.com/moonlight-stream/moonlight-qt/commit/76deafbd7bf868562d69061e7d6abf2612a2c7ad.patch";
      hash = "sha256-+rXdexZQpOP6yS+oTmvYVxasWxOX16uU1udN75zNX3w=";
    })
  ];

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
    pkg-config
    vulkan-headers
  ];

  buildInputs = [
    SDL2
    SDL2_ttf
    ffmpeg
    libopus
    libplacebo
    qt6.qtdeclarative
    qt6.qtsvg
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    libpulseaudio
    libva
    libvdpau
    libxkbcommon
    qt6.qtwayland
    wayland
    libdrm
    # streaming/video/ffmpeg-renderers/renderer.h pulls in SDL_egl.h, which
    # opens with #include <EGL/egl.h>, and the EGL renderer is compiled in
    # (-DHAVE_EGL). Nothing here declared a provider for that header:
    #
    #   SDL_egl.h:32:10: fatal error: EGL/egl.h: No such file or directory
    #
    # It resolved before only by leaking out of the buildPlatform qtbase
    # reached via qt6.qmake in nativeBuildInputs, whose closure carries
    # libglvnd -- i.e. the hostPlatform compile was reading buildPlatform
    # headers. Declare it on the platform that actually needs it.
    libGL
  ];

  qmakeFlags = [
    "CONFIG+=disable-prebuilts"
    # Declaring libGL as a buildInput is not enough to make <EGL/egl.h>
    # reachable here. qmake configures against the linux-g++ mkspec, whose
    # QMAKE_CXX is a bare `g++` -- so the compile runs under the buildPlatform
    # wrapper, which reads NIX_CFLAGS_COMPILE_FOR_BUILD and never sees the
    # -isystem a hostPlatform buildInput contributes. Every other include on
    # that command line is there explicitly, emitted by qmake from PKGCONFIG or
    # INCLUDEPATH; libGL was the only one relying on wrapper injection. So put
    # it on the command line the same way the rest get there.
    #
    # libvdpau is the same case: streaming/video/ffmpeg-renderers/vdpau.h
    # includes <vdpau/vdpau.h> and <vdpau/vdpau_x11.h>, and the VDPAU renderer
    # is compiled in, but nothing emits a -I for it. Of the system headers this
    # source includes directly -- libdrm, va, vdpau, wayland -- every other one
    # already arrives explicitly through PKGCONFIG; these two were the only
    # gaps.
    "INCLUDEPATH+=${lib.getDev libGL}/include"
    "INCLUDEPATH+=${lib.getDev libvdpau}/include"
    # And vulkan-headers, reached indirectly: libplacebo/vulkan.h opens with
    # #include <vulkan/vulkan.h>, and the libplacebo Vulkan path is compiled in
    # (-DHAVE_LIBPLACEBO_VULKAN). It is listed in nativeBuildInputs, which does
    # not reach this compile either -- the earlier assumption that a
    # nativeBuildInput's headers would arrive here, since the compiler is the
    # buildPlatform wrapper, turned out to be wrong:
    #
    #   libplacebo/vulkan.h:21:10: fatal error: vulkan/vulkan.h: No such file
    #
    # Pure headers, so platform is immaterial; routed the same way as the rest.
    "INCLUDEPATH+=${vulkan-headers}/include"
  ];

  # During buildPhase, qmake re-runs for sub-projects that lack a Makefile
  # (moonlight-common-c). Qt's link_pkgconfig.prf calls bare `pkg-config`,
  # but in intra-ISA cross builds the only pkg-config binary in PATH is
  # `${hostPlatform.config}-pkg-config` (the HOST wrapper). Resolve it at
  # build time and alias it as plain `pkg-config` so qmake finds it and
  # PKG_CONFIG_PATH (populated with HOST .pc dirs by the strictDeps relax)
  # actually gets searched.
  preBuild = lib.optionalString stdenv.isIntraISACross ''
    _moonlight_tmpbin=$(mktemp -d)
    _hostPkgConfig=$(command -v "${stdenv.hostPlatform.config}-pkg-config" 2>/dev/null || true)
    if [ -n "$_hostPkgConfig" ]; then
      ln -s "$_hostPkgConfig" "$_moonlight_tmpbin/pkg-config"
      export PATH="$_moonlight_tmpbin:$PATH"
    fi
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir $out/Applications $out/bin
    mv app/Moonlight.app $out/Applications
    ln -s $out/Applications/Moonlight.app/Contents/MacOS/Moonlight $out/bin/moonlight
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    changelog = "https://github.com/moonlight-stream/moonlight-qt/releases/tag/v${finalAttrs.version}";
    description = "Play your PC games on almost any device";
    homepage = "https://moonlight-stream.org";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [
      azuwis
      zmitchell
    ];
    platforms = lib.platforms.all;
    mainProgram = "moonlight";
  };
})
