{
  lib,
  stdenv,
  bashNonInteractive,
  buildPackages,
  fetchurl,
  perl,
  bdftopcf,
  bdf2psf,
  imagemagick,
}:

let
  # `perl` is spliced, so listing it directly in nativeBuildInputs would
  # select the build-platform variant. `.withPackages` returns a plain
  # derivation and drops that splice metadata, so the two environments have
  # to be constructed separately -- otherwise nativeBuildInputs silently
  # receives the host-platform env.
  #
  # The build runs bin/unihex2png (and friends) to generate glyphs, so it
  # needs a perl that executes on the BUILD platform.
  perlenvBuild = buildPackages.perl.withPackages (ps: [ ps.GD ]);
  # Installed scripts in $bin keep perl shebangs, patched against the HOST
  # platform, so the host env is still a genuine runtime dependency.
  perlenvHost = perl.withPackages (ps: [ ps.GD ]);
in
stdenv.mkDerivation (finalAttrs: {
  pname = "unifont";
  version = "17.0.05";

  strictDeps = true;

  src = fetchurl {
    url = "mirror://gnu/unifont/unifont-${finalAttrs.version}/unifont-${finalAttrs.version}.tar.gz";
    hash = "sha256-8ofP+ybiJyOqNuZoSGmw8/87+4IsSwEAi9hHkR7BtjE=";
  };

  postPatch = ''
    rm -r font/precompiled
    patchShebangs ./src
    ${lib.optionalString (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      substituteInPlace Makefile --replace-fail \
        'bin/unigenwidth ' \
        '$(BINDIR)/unigenwidth '
      substituteInPlace font/Makefile --replace-fail \
        '"BINDIR:../../../$(BINDIR)/"' \
        '"BINDIR:$(BINDIR)/"'
    ''}
  '';

  nativeBuildInputs = [
    perlenvBuild
    bdftopcf
    bdf2psf
    imagemagick
  ];

  # bashNonInteractive is upstream's own addition, unrelated to the
  # BUILD/HOST perl split above -- kept as-is. `perlenv` (a single
  # perl.withPackages upstream used for both nativeBuildInputs and
  # buildInputs) is NOT: it is the plain HOST-platform perl with no splice
  # metadata, which is the exact bug perlenvBuild/perlenvHost exists to
  # avoid -- see the `let` block. perlenvHost is its replacement here.
  buildInputs = [
    bashNonInteractive
    perlenvHost
  ];

  makeFlags = [
    "PREFIX=${placeholder "out"}"
  ]
  ++ lib.optionals (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) [
    "BINDIR=${buildPackages.unifont.bin}/bin"
  ];

  buildFlags = [ "BUILDFONT=1" ];

  # The `sample` variants are not intended for general use.
  #
  # From the 2013 changelog:
  #
  # > These "Unifont Sample" fonts contain combining circles, and four-digit
  # > hexadecimal glyphs for unassigned code points and Private Use Area glyphs.
  # > Because of the inclusion of combining cirlces, "Unifont Sample" font
  # > versions are only intended for illustrating individual glyphs, not for
  # > general-purpose writing.
  postInstall = ''
    moveToOutput bin "$bin"
    moveToOutput share/unifont "$doc"

    # Move `sample` into its own output.
    mkdir -vp "$sample/share/fonts/X11/misc/"
    mkdir -vp "$sample/share/fonts/opentype/unifont/"
    mv -vt "$sample/share/fonts/X11/misc/" \
      "$out"/share/fonts/X11/misc/*_sample.*
    mv -vt "$sample/share/fonts/opentype/unifont/" \
      "$out"/share/fonts/opentype/unifont/*_sample.*
  '';

  postFixup = ''
    patchShebangs --host --update "$bin"
  '';

  outputs = [
    "out"
    "bin"
    "doc"
    "man"
    "info"
    "sample"
  ];

  # Don't bloat the font output with tools
  propagatedBuildOutputs = [ ];

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Unicode font for Base Multilingual Plane";
    homepage = "https://unifoundry.com/unifont/";

    # Basically GPL2+ with font exception.
    license = with lib.licenses; [
      gpl2Plus
      fontException
    ];
    maintainers = with lib.maintainers; [
      rycee
      qweered
    ];
    platforms = lib.platforms.all;
  };
})
