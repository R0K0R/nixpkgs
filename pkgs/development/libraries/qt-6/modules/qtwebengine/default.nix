{
  qtModule,
  fetchzip,
  qtdeclarative,
  qtwebchannel,
  qtpositioning,
  qtwebsockets,
  buildPackages,
  bison,
  coreutils,
  flex,
  gperf,
  ninja,
  pkg-config,
  python3,
  which,
  nodejs,
  libxext,
  libxdamage,
  libxcomposite,
  xrandr,
  libxkbfile,
  libpciaccess,
  libxcursor,
  libxscrnsaver,
  libxrandr,
  libxtst,
  libxshmfence,
  libxi,
  cups,
  fontconfig,
  freetype,
  harfbuzz,
  icu,
  dbus,
  expat,
  libdrm,
  zlib,
  minizip,
  libjpeg,
  libpng,
  libtiff,
  libwebp,
  libopus,
  jsoncpp,
  protobuf,
  srtp,
  snappy,
  nss,
  libevent,
  openssl,
  alsa-lib,
  pulseaudio,
  libcap,
  pciutils,
  pipewire,
  gn,
  ffmpeg,
  lib,
  stdenv,
  glib,
  libxml2,
  libxslt,
  lcms2,
  libkrb5,
  libgbm,
  libva,
  enableProprietaryCodecs ? true,
  # darwin
  bootstrap_cmds,
  cctools,
  xcbuild,
}:

qtModule {
  pname = "qtwebengine";

  version = "6.140.0-rc";
  src = fetchzip {
    url = "https://download.qt.io/development_releases/qtwebengine/6.140.0-rc/qtwebengine-everywhere-src-6.140.0-rc.tar.xz";
    hash = "sha256-ij7oWNkbzf98FwKjhub3lyvDb32G4qFtUiYJvdlw01Y=";
  };

  nativeBuildInputs = [
    bison
    coreutils
    flex
    gperf
    ninja
    pkg-config
    (python3.withPackages (ps: with ps; [ html5lib ]))
    which
    nodejs
  ]
  # In cross builds, FindGn.cmake requires exactly QT_REPO_MODULE_VERSION
  # (6.140.0 for this release). The stock nixpkgs gn reports "2341" (upstream
  # GN revision) -> version mismatch -> Gn_FOUND=FALSE -> FATAL_ERROR. Use the
  # Qt-patched gn (built by qt6Gn from src/3rdparty/gn/) which reports
  # "6.140.0.qtwebengine.qt.io" and satisfies the exact version requirement.
  # In native builds, gn's version still mismatches, but the FATAL_ERROR path
  # isn't reached (CMAKE_CROSSCOMPILING=FALSE) -- qtwebengine builds its own
  # gn from source via ExternalProject_Add instead, so native builds keep
  # using the system gn in PATH (find_program fails to satisfy Gn_FOUND and
  # falls through to that path, unaffected either way).
  ++ (
    if !stdenv.buildPlatform.canExecute stdenv.hostPlatform then
      [ buildPackages.qt6.qt6Gn ]
    else
      [ gn ]
  )
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    bootstrap_cmds
    cctools
    xcbuild
  ];
  doCheck = true;
  outputs = [
    "out"
    "dev"
  ];

  dontUseGnConfigure = true;

  # ninja builds some components with -Wno-format,
  # which cannot be set at the same time as -Wformat-security
  hardeningDisable = [ "format" ];

  patches = [
    # Don't assume /usr/share/X11, and also respect the XKB_CONFIG_ROOT
    # environment variable, since NixOS relies on it working.
    # See https://github.com/NixOS/nixpkgs/issues/226484 for more context.
    ./xkb-includes.patch

    ./link-pulseaudio.patch

    # Override locales install path so they go to QtWebEngine's $out
    ./locales-path.patch

    # Look for things in the right places in our split-prefix config
    ./split-prefix.patch

    # Reproducibility QTBUG-136068
    ./gn-object-sorted.patch

    # Don't require compiler to identify as AppleClang on Darwin
    ./darwin-compiler.patch

    # Disable Metal shader precompilation, which requires Apple proprietary tools
    ./darwin-no-metal.patch

    # Generating debug symbols fails the build because it can't find dsymutil
    # FIXME: figure out how to fix this properly
    ./darwin-no-debug-symbols.patch

    # Darwin toolchain fixes
    # FIXME: do we still need these?
    ./clang-base-path-from-cmake-compiler.patch
    ./lflags-remove-strip-darwin-isysroot.patch
  ];

  postPatch = ''
    # Patch Chromium build tools
    (cd src/3rdparty/chromium; patchShebangs .)
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace cmake/QtToolchainHelpers.cmake \
      --replace-fail "/usr/bin/xcrun" "${xcbuild}/bin/xcrun"
  '';

  cmakeFlags = [
    "-DQT_FEATURE_qtpdf_build=ON"
    "-DQT_FEATURE_qtpdf_widgets_build=ON"
    "-DQT_FEATURE_qtpdf_quick_build=ON"
    "-DQT_FEATURE_pdf_v8=ON"
    "-DQT_FEATURE_pdf_xfa=ON"
    "-DQT_FEATURE_pdf_xfa_bmp=ON"
    "-DQT_FEATURE_pdf_xfa_gif=ON"
    "-DQT_FEATURE_pdf_xfa_png=ON"
    "-DQT_FEATURE_pdf_xfa_tiff=ON"
    "-DQT_FEATURE_webengine_system_libevent=ON"
    "-DQT_FEATURE_webengine_system_ffmpeg=ON"
    # android only. https://bugreports.qt.io/browse/QTBUG-100293
    # "-DQT_FEATURE_webengine_native_spellchecker=ON"
    "-DQT_FEATURE_webengine_kerberos=ON"
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    "-DQT_FEATURE_webengine_system_libxml=ON"
    "-DQT_FEATURE_webengine_webrtc_pipewire=ON"

    # Appears not to work on some platforms
    # https://github.com/Homebrew/homebrew-core/issues/104008
    "-DQT_FEATURE_webengine_system_icu=ON"
  ]
  ++ lib.optionals enableProprietaryCodecs [
    "-DQT_FEATURE_webengine_proprietary_codecs=ON"
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=12.0" # Per Qt 6’s deployment target (why doesn’t the hook work?)
    "-DCMAKE_CXX_COMPILER=${lib.getExe' stdenv.cc "clang++"}"
  ];

  propagatedBuildInputs = [
    qtdeclarative
    qtwebchannel
    qtwebsockets
    qtpositioning

    # Image formats
    libjpeg
    libpng
    libtiff
    libwebp

    # Video formats
    srtp

    # Audio formats
    libopus

    # Text rendering
    harfbuzz

    openssl
    glib
    libxslt
    lcms2

    libevent
    ffmpeg
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    dbus
    expat
    zlib
    minizip
    snappy
    nss
    protobuf
    jsoncpp

    icu
    libxml2

    # Audio formats
    alsa-lib
    pulseaudio

    # Text rendering
    fontconfig
    freetype

    libcap
    pciutils

    # X11 libs
    xrandr
    libxscrnsaver
    libxcursor
    libxrandr
    libpciaccess
    libxtst
    libxcomposite
    libxdamage
    libdrm
    libxkbfile
    libxshmfence
    libxi
    libxext

    # Pipewire
    pipewire

    libkrb5
    libgbm
    libva
  ];

  buildInputs = [
    cups
  ];

  requiredSystemFeatures = [ "big-parallel" ];

  postConfigure =
    # cmake's create_pkg_config_host_wrapper() generates
    # pkg-config-host_wrapper.sh, which unsets PKG_CONFIG_PATH before calling
    # the nix HOST pkg-config wrapper. The nix wrapper's own variable
    # accumulation reads plain PKG_CONFIG_PATH to populate its salted
    # PKG_CONFIG_PATH_<salt> variable; finding it unset leaves that empty, so
    # the wrapped pkg-config runs with no search paths and can't find e.g.
    # icu-i18n. Remove only the PKG_CONFIG_PATH unset (keep the
    # LIBDIR/SYSROOT_DIR ones) so HOST .pc paths survive into GN's
    # pkg_config() calls.
    lib.optionalString (!(stdenv.buildPlatform.canExecute stdenv.hostPlatform)) ''
      find "$PWD" -name "pkg-config-host_wrapper.sh" | while IFS= read -r f; do
        sed -i '/^unset PKG_CONFIG_PATH$/d' "$f"
      done
    '';

  preConfigure =
    # FindPkgConfigHost.cmake searches for plain "pkg-config" with
    # NO_SYSTEM_ENVIRONMENT_PATH (skipping PATH entirely), but checks
    # $ENV{PKG_CONFIG_HOST} first, so point that at the prefixed HOST
    # pkg-config wrapper.
    #
    # Also set PKG_CONFIG so cmake's find_package(PkgConfig) resolves to the
    # HOST pkg-config: QtToolchainHelpers.cmake's append_pkg_config_setup()
    # sets the GN arg pkg_config="${PKG_CONFIG_EXECUTABLE}", and without this,
    # cmake finds the BUILD-side pkg-config (which has no HOST library
    # paths), so GN's pkg_config("system_icui18n") call fails with "Could not
    # run pkg-config" (pkg-config exits 1 for unknown packages).
    lib.optionalString (!(stdenv.buildPlatform.canExecute stdenv.hostPlatform)) ''
      _hostPkgConfig=$(command -v "${stdenv.hostPlatform.config}-pkg-config" 2>/dev/null || true)
      if [ -n "$_hostPkgConfig" ]; then
        export PKG_CONFIG_HOST="$_hostPkgConfig"
        export PKG_CONFIG="$_hostPkgConfig"
      fi
    ''
    + ''
      export NINJAFLAGS="-j$NIX_BUILD_CORES"
    '';

  # Debug info is too big to link with LTO.
  separateDebugInfo = false;

  # Add dlopen-only dependencies after shrink-rpath, which would remove them.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --add-rpath "${
      lib.makeLibraryPath [
        pipewire
        pciutils
      ]
    }" "$out/lib/libQt6WebEngineCore.so"
  '';

  meta = {
    description = "Web engine based on the Chromium web browser";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "armv7a-linux"
      "armv7l-linux"
      "x86_64-linux"
    ];
    # This build takes a long time; particularly on slow architectures
    # 1 hour on 32x3.6GHz -> maybe 12 hours on 4x2.4GHz
    timeout = 24 * 3600;
  };
}
