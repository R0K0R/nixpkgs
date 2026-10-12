{
  buildPackages,
  writeText,
  fontconfig,
  lib,
  runCommand,
  stdenv,
}:
let
  fontconfig' = fontconfig;
in
{
  fontconfig ? fontconfig',
  fontDirectories,
}:

let
  # The cache is keyed by architecture, so it is made by the host's fc-cache, under an
  # emulator when the build platform can't run it. With the same triple and fontconfig
  # version, the build platform's fc-cache writes the same cache: there it is used
  # instead of the emulator, which need not implement every host instruction (qemu's
  # TCG has no GFNI, which gcc emits for -march=meteorlake, e.g. in freetype).
  fcCache =
    if
      !stdenv.buildPlatform.canExecute stdenv.hostPlatform
      && stdenv.buildPlatform.config == stdenv.hostPlatform.config
      && buildPackages.fontconfig.version == fontconfig.version
    then
      lib.getExe' buildPackages.fontconfig "fc-cache"
    else
      "${stdenv.hostPlatform.emulator buildPackages} ${lib.getExe' fontconfig "fc-cache"}";

  fontDirsPath = writeText "font-dirs" ''
    <!-- Font directories -->
    ${lib.concatStringsSep "\n" (map (font: "<dir>${font}</dir>") fontDirectories)}
  '';
in
runCommand "fc-cache"
  {
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  ''
    export FONTCONFIG_FILE=$(pwd)/fonts.conf

    cat > fonts.conf << EOF
    <?xml version='1.0'?>
    <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
    <fontconfig>
      <include>${fontconfig.out}/etc/fonts/fonts.conf</include>
      <cachedir>$out</cachedir>
    EOF
    cat "${fontDirsPath}" >> fonts.conf
    echo "</fontconfig>" >> fonts.conf

    # N.B.: fc-cache keys its cache entries by architecture.
    # We must invoke the host `fc-cache` (not the build fontconfig) if we want
    # the cache to be usable by the host.
    mkdir -p $out
    ${fcCache} -sv

    # This is not a cache dir in the normal sense -- it won't be automatically
    # recreated.
    rm -f "$out/CACHEDIR.TAG"
  ''
