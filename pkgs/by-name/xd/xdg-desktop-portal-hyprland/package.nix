{
  lib,
  gcc16Stdenv,
  fetchFromGitHub,
  cmake,
  makeWrapper,
  pkg-config,
  nix-update-script,
  grim,
  hyprland-protocols,
  hyprlang,
  hyprtoolkit,
  hyprwayland-scanner,
  libgbm,
  libuuid,
  pipewire,
  sdbus-cpp_2,
  slurp,
  wayland-protocols,
  wayland-scanner,
  debug ? false,
}:
gcc16Stdenv.mkDerivation (finalAttrs: {
  pname = "xdg-desktop-portal-hyprland";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "xdg-desktop-portal-hyprland";
    tag = "v${finalAttrs.version}";
    hash = "sha256-uyd3OAvtB2TJ9Y1RooCyLr6dlFUZKDmac5QtMbbPq4c=";
  };

  depsBuildBuild = [
    pkg-config
  ];

  nativeBuildInputs = [
    cmake
    makeWrapper
    pkg-config
    hyprwayland-scanner
  ];

  buildInputs = [
    hyprland-protocols
    hyprlang
    hyprtoolkit
    libgbm
    libuuid
    pipewire
    sdbus-cpp_2
    wayland-protocols
    wayland-scanner
    # CMakeLists.txt:56 does a single pkg_check_modules() call that bundles
    # hyprwayland-scanner in with genuine buildInputs (wayland-client,
    # libpipewire, libdrm, hyprlang, hyprutils, ...). That query goes through
    # the hostPlatform pkg-config, but hyprwayland-scanner was listed only in
    # nativeBuildInputs, so its .pc lived in the buildPlatform search path
    # instead and the check came back NOTFOUND:
    #
    #   No package 'hyprwayland-scanner' found
    #
    # Genuinely wanted on both platforms, same shape as wayland-scanner above:
    # the scanner binary to run at build time, and the .pc to satisfy this
    # check.
    hyprwayland-scanner
  ];

  cmakeBuildType = if debug then "Debug" else "RelWithDebInfo";

  dontStrip = debug;
  separateDebugInfo = !debug;

  doCheck = true;

  postInstall = ''
    wrapProgramShell $out/bin/hyprland-share-picker \
      --prefix PATH ":" ${lib.makeBinPath [ slurp ]}

    wrapProgramShell $out/libexec/xdg-desktop-portal-hyprland \
      --prefix PATH ":" ${
        lib.makeBinPath [
          (placeholder "out")
          grim
          slurp
        ]
      }
  '';

  passthru = {
    updateScript = nix-update-script { };
  };

  meta = {
    description = "xdg-desktop-portal backend for Hyprland";
    homepage = "https://github.com/hyprwm/xdg-desktop-portal-hyprland";
    changelog = "https://github.com/hyprwm/xdg-desktop-portal-hyprland/releases/tag/v${finalAttrs.version}";
    mainProgram = "hyprland-share-picker";
    license = lib.licenses.bsd3;
    teams = [ lib.teams.hyprland ];
    platforms = lib.platforms.linux;
  };
})
