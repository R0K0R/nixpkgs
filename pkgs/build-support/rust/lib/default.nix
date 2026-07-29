{
  lib,
  stdenv,
  pkgsBuildHost,
  pkgsBuildTarget,
  pkgsTargetTarget,
}:

{
  # These environment variables must be set when using `cargo-c` and
  # several other tools which do not deal well with cross
  # compilation.  The symptom of the problem they fix is errors due
  # to buildPlatform CFLAGS being passed to the
  # hostPlatform-targeted compiler -- for example, `-m64` being
  # passed on a build=x86_64/host=aarch64 compilation.
  envVars =
    let

      ccForBuild = "${pkgsBuildHost.stdenv.cc}/bin/${pkgsBuildHost.stdenv.cc.targetPrefix}cc";
      cxxForBuild = "${pkgsBuildHost.stdenv.cc}/bin/${pkgsBuildHost.stdenv.cc.targetPrefix}c++";

      ccForHost = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}cc";
      cxxForHost = "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}c++";

      # Unfortunately we must use the dangerous `pkgsTargetTarget` here
      # because hooks are artificially phase-shifted one slot earlier
      # (they go in nativeBuildInputs, so the hostPlatform looks like
      # a targetPlatform to them).
      ccForTarget = "${pkgsTargetTarget.stdenv.cc}/bin/${pkgsTargetTarget.stdenv.cc.targetPrefix}cc";
      cxxForTarget = "${pkgsTargetTarget.stdenv.cc}/bin/${pkgsTargetTarget.stdenv.cc.targetPrefix}c++";

      rustBuildPlatform = stdenv.buildPlatform.rust.rustcTarget;
      rustBuildPlatformSpec = stdenv.buildPlatform.rust.rustcTargetSpec;
      rustHostPlatform = stdenv.hostPlatform.rust.rustcTarget;
      rustHostPlatformSpec = stdenv.hostPlatform.rust.rustcTargetSpec;
      rustTargetPlatform = stdenv.targetPlatform.rust.rustcTarget;
      rustTargetPlatformSpec = stdenv.targetPlatform.rust.rustcTargetSpec;
    in
    {
      inherit
        ccForBuild
        cxxForBuild
        rustBuildPlatform
        rustBuildPlatformSpec
        ccForHost
        cxxForHost
        rustHostPlatform
        rustHostPlatformSpec
        ccForTarget
        cxxForTarget
        rustTargetPlatform
        rustTargetPlatformSpec
        ;

      # Prefix this onto a command invocation in order to set the
      # variables needed by cargo.
      #
      setEnv = ''
        env \
      ''
      # The build- and host-platform variable names collide whenever the two
      # platforms share a rust target triple but are not the same package set
      # -- an intra-ISA cross, e.g. build x86_64-unknown-linux-gnu and host the
      # same triple with gcc.arch set. Both blocks then expand to the *same*
      # variable names, `env` places both assignments in the environment, and
      # getenv() returns the first match, so the buildPlatform compiler silently
      # wins for hostPlatform code. Observed as a hostPlatform Rust binary being
      # linked by the buildPlatform cc-wrapper, which does not carry the
      # hostPlatform's -L paths:
      #
      #   ld.bfd: cannot find -lpam: No such file or directory
      #
      # even though pam is a perfectly ordinary buildInput.
      #
      # Omit the buildPlatform assignments when they would collide; the
      # hostPlatform block below sets the same names, and in a genuinely native
      # build it sets them to the same values anyway. This mirrors the
      # rustTargetPlatform != rustHostPlatform guard already applied further
      # down for exactly the same class of collision.
      + lib.optionalString (rustBuildPlatform != rustHostPlatform) ''
        "CC_${stdenv.buildPlatform.rust.cargoEnvVarTarget}=${ccForBuild}" \
        "CXX_${stdenv.buildPlatform.rust.cargoEnvVarTarget}=${cxxForBuild}" \
        "CARGO_TARGET_${stdenv.buildPlatform.rust.cargoEnvVarTarget}_LINKER=${ccForBuild}" \
      ''
      + ''
        "CARGO_BUILD_TARGET=${rustBuildPlatform}" \
        "HOST_CC=${pkgsBuildHost.stdenv.cc}/bin/cc" \
        "HOST_CXX=${pkgsBuildHost.stdenv.cc}/bin/c++" \
      ''
      + ''
        "CC_${stdenv.hostPlatform.rust.cargoEnvVarTarget}=${ccForHost}" \
        "CXX_${stdenv.hostPlatform.rust.cargoEnvVarTarget}=${cxxForHost}" \
        "CARGO_TARGET_${stdenv.hostPlatform.rust.cargoEnvVarTarget}_LINKER=${ccForHost}" \
      ''
      # Due to a bug in how splicing and pkgsTargetTarget works, in
      # situations where pkgsTargetTarget is irrelevant
      # pkgsTargetTarget.stdenv.cc is often simply wrong.  We must omit
      # the following lines when rustTargetPlatform collides with
      # rustHostPlatform.
      + lib.optionalString (rustTargetPlatform != rustHostPlatform) ''
        "CC_${stdenv.targetPlatform.rust.cargoEnvVarTarget}=${ccForTarget}" \
        "CXX_${stdenv.targetPlatform.rust.cargoEnvVarTarget}=${cxxForTarget}" \
        "CARGO_TARGET_${stdenv.targetPlatform.rust.cargoEnvVarTarget}_LINKER=${ccForTarget}" \
      '';
    };
}
//
  lib.mapAttrs
    (
      old: new: platform:
      lib.warn
        "`rust.${old} platform` is deprecated. Use `platform.rust.${lib.showAttrPath new}` instead."
        lib.getAttrFromPath
        new
        platform.rust
    )
    {
      toTargetArch = [
        "platform"
        "arch"
      ];
      toTargetOs = [
        "platform"
        "os"
      ];
      toTargetFamily = [
        "platform"
        "target-family"
      ];
      toTargetVendor = [
        "platform"
        "vendor"
      ];
      toRustTarget = [ "rustcTarget" ];
      toRustTargetSpec = [ "rustcTargetSpec" ];
      toRustTargetSpecShort = [ "cargoShortTarget" ];
      toRustTargetForUseInEnvVars = [ "cargoEnvVarTarget" ];
      IsNoStdTarget = [ "isNoStdTarget" ];
    }
