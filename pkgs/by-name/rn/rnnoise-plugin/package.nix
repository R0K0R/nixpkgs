{
  lib,
  stdenv,
  buildPackages,
  cmake,
  fetchFromGitHub,
  freetype,
  gtk3-x11,
  pcre2,
  pkg-config,
  webkitgtk_4_1,
  libxrandr,
  libx11,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "rnnoise-plugin";
  version = "1.10";
  outputs = [
    "out"
    "ladspa"
    "lv2"
    "lxvst"
    "vst3"
  ];

  src = fetchFromGitHub {
    owner = "werman";
    repo = "noise-suppression-for-voice";
    rev = "v${finalAttrs.version}";
    sha256 = "sha256-sfwHd5Fl2DIoGuPDjELrPp5KpApZJKzQikCJmCzhtY8=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ]
  # This vendors JUCE, which spawns a subprocess cmake invocation to build
  # juceaide (its native code-gen tool); that subprocess searches PATH for
  # plain 'cc'/'gcc' rather than trusting the outer build's $CC. A cross
  # cc-wrapper only provides triple-prefixed names, so the subprocess cmake
  # fails with "No CMAKE_C_COMPILER could be found". Put the BUILD-platform
  # cc-wrapper's plain-named binaries on PATH so juceaide's own subprocess
  # build can find a compiler.
  ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    buildPackages.stdenv.cc
  ];

  patches = lib.optionals stdenv.hostPlatform.isDarwin [
    # Ubsan seems to be broken on aarch64-darwin, it produces linker errors similar to https://github.com/NixOS/nixpkgs/issues/140751
    ./disable-ubsan.patch
  ];

  buildInputs = [
    freetype
    gtk3-x11
    pcre2
    libx11
    libxrandr
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    webkitgtk_4_1
  ];

  # Move each plugin into a dedicated output, leaving a symlink in $out for backwards compatibility
  postInstall = ''
    for plugin in ladspa lv2 lxvst vst3; do
      mkdir -p ''${!plugin}/lib
      mv $out/lib/$plugin ''${!plugin}/lib/$plugin
      ln -s ''${!plugin}/lib/$plugin $out/lib/$plugin
    done
  '';

  meta = {
    description = "Real-time noise suppression plugin for voice based on Xiph's RNNoise";
    homepage = "https://github.com/werman/noise-suppression-for-voice";
    license = lib.licenses.gpl3;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [
      panaeon
      henrikolsson
      sciencentistguy
    ];
  };
})
