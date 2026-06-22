{
  lib,
  stdenv,
  perl,
  toPerlModule,
}:

{
  buildInputs ? [ ],
  nativeBuildInputs ? [ ],
  outputs ? [
    "out"
    "devdoc"
  ],

  # enabling or disabling does nothing for perl packages so set it explicitly
  # to false to not change hashes when enableParallelBuildingByDefault is enabled
  enableParallelBuilding ? false,

  doCheck ? true,
  checkTarget ? "test",

  # Prevent CPAN downloads.
  PERL_AUTOINSTALL ? "--skipdeps",

  # From http://wiki.cpantesters.org/wiki/CPANAuthorNotes: "allows
  # authors to skip certain tests (or include certain tests) when
  # the results are not being monitored by a human being."
  AUTOMATED_TESTING ? true,

  # current directory (".") is removed from @INC in Perl 5.26 but many old libs rely on it
  # https://metacpan.org/pod/release/XSAWYERX/perl-5.26.0/pod/perldelta.pod#Removal-of-the-current-directory-%28%22.%22%29-from-@INC
  PERL_USE_UNSAFE_INC ? "1",

  env ? { },

  postPatch ? "patchShebangs .",

  ...
}@attrs:

lib.throwIf (attrs ? name)
  "buildPerlPackage: `name` (\"${attrs.name}\") is deprecated, use `pname` and `version` instead"

  (
    let
      defaultMeta = {
        homepage = "https://metacpan.org/dist/${attrs.pname}";
        inherit (perl.meta) platforms;
      };

      package = stdenv.mkDerivation (
        attrs
        // {
          name = "perl${perl.version}-${attrs.pname}-${attrs.version}";

          builder = ./builder.sh;

          buildInputs = buildInputs ++ [ perl ];
          nativeBuildInputs =
            nativeBuildInputs
            ++ (
              if stdenv.isPseudoCross or false then
                # In pseudo-cross (same triple, different gcc.arch) canExecute returns
                # false, so the normal path would use perl.mini (no dynamic loading).
                # But HOST perl is compiled with arch-specific flags (e.g. -march=
                # meteorlake with Intel-only instructions) that may SIGILL on the
                # BUILD machine (e.g. AMD znver5).  Use the BUILD-native full perl
                # instead: it runs safely on BUILD, has dynamic loading, and installs
                # to the same lib/perl5/X/x86_64-linux path as HOST perl (perl's arch
                # string is not affected by micro-arch tuning, only by CPU family).
                [ (perl.__spliced.buildBuild or perl) ]
              else if !(stdenv.buildPlatform.canExecute stdenv.hostPlatform) then
                [ perl.mini ]
              else
                [ perl ]
            );

          inherit
            outputs
            doCheck
            checkTarget
            enableParallelBuilding
            postPatch
            ;
          env = {
            inherit PERL_AUTOINSTALL AUTOMATED_TESTING PERL_USE_UNSAFE_INC;
            fullperl = perl.__spliced.buildHost or perl;
          }
          // env;

          meta = defaultMeta // (attrs.meta or { });
        }
      );

    in
    toPerlModule package
  )
