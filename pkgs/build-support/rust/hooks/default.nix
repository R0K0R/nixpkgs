{
  cargo-nextest,
  clang,
  diffutils,
  lib,
  makeSetupHook,
  rust,
  stdenv,
  pkgsHostTarget,
  pkgsTargetTarget,

  # This confusingly-named parameter indicates the *subdirectory of
  # `target/` from which to copy the build artifacts.  It is derived
  # from a stdenv platform (or a JSON file).
  target ? stdenv.targetPlatform.rust.cargoShortTarget,
  tests,
  pkgsCross,
}:
{
  cargoBuildHook = makeSetupHook {
    name = "cargo-build-hook.sh";
    substitutions = {
      inherit (stdenv.targetPlatform.rust) rustcTargetSpec;
      inherit (rust.envVars) setEnv;

    };
    passthru.tests = {
      test = tests.rust-hooks.cargoBuildHook;
      ${if stdenv.hostPlatform.isLinux then "testCross" else null} =
        pkgsCross.riscv64.tests.rust-hooks.cargoBuildHook;
    };
    meta.license = lib.licenses.mit;
  } ./cargo-build-hook.sh;

  cargoCheckHook = makeSetupHook {
    name = "cargo-check-hook.sh";
    substitutions = {
      inherit (stdenv.targetPlatform.rust) rustcTargetSpec;
      inherit (rust.envVars) setEnv;
    };
    passthru.tests = {
      test = tests.rust-hooks.cargoCheckHook;
      ${if stdenv.hostPlatform.isLinux then "testCross" else null} =
        pkgsCross.riscv64.tests.rust-hooks.cargoCheckHook;
    };
    meta.license = lib.licenses.mit;
  } ./cargo-check-hook.sh;

  cargoInstallHook = makeSetupHook {
    name = "cargo-install-hook.sh";
    substitutions = {
      targetSubdirectory = target;
    };
    passthru.tests = {
      test = tests.rust-hooks.cargoInstallHook;
      ${if stdenv.hostPlatform.isLinux then "testCross" else null} =
        pkgsCross.riscv64.tests.rust-hooks.cargoInstallHook;
    };
    meta.license = lib.licenses.mit;
  } ./cargo-install-hook.sh;

  cargoNextestHook = makeSetupHook {
    name = "cargo-nextest-hook.sh";
    propagatedBuildInputs = [ cargo-nextest ];
    substitutions = {
      inherit (stdenv.targetPlatform.rust) rustcTargetSpec;
    };
    passthru.tests = {
      test = tests.rust-hooks.cargoNextestHook;
      ${if stdenv.hostPlatform.isLinux then "testCross" else null} =
        pkgsCross.riscv64.tests.rust-hooks.cargoNextestHook;
    };
    meta.license = lib.licenses.mit;
  } ./cargo-nextest-hook.sh;

  cargoSetupHook = makeSetupHook {
    name = "cargo-setup-hook.sh";
    substitutions = {
      defaultConfig = ../fetchcargo-default-config.toml;

      # Specify the stdenv's `diff` by abspath to ensure that the user's build
      # inputs do not cause us to find the wrong `diff`.
      diff = "${lib.getBin diffutils}/bin/diff";

      cargoConfig =
        lib.optionalString (stdenv.hostPlatform.config != stdenv.targetPlatform.config) ''
          [target."${stdenv.targetPlatform.rust.rustcTarget}"]
          "linker" = "${pkgsTargetTarget.stdenv.cc}/bin/${pkgsTargetTarget.stdenv.cc.targetPrefix}cc"
          "rustflags" = [ ${
            lib.concatStringsSep ", " (
              [
                ''"-Ctarget-feature=${if stdenv.targetPlatform.isStatic then "+" else "-"}crt-static"''
              ]
              ++ lib.optional (!stdenv.targetPlatform.isx86_32) ''"-Cforce-frame-pointers=yes"''
            )
          } ]
        ''
        + (
          let
            # These hooks are phase-shifted one slot earlier (they live in
            # nativeBuildInputs), so `targetPlatform` here is the platform the
            # package is actually being built FOR, and `stdenv.cc` is the
            # buildPlatform compiler -- see the same note in
            # build-support/rust/lib/default.nix.
            #
            # The block above, which carries the correct target compiler, is
            # emitted only when the two platforms differ by *config string*. On
            # an intra-ISA cross -- same triple, differing only in e.g. gcc.arch
            # -- the strings match, so it is skipped and this block becomes the
            # only [target."..."] table. It must then supply the target
            # compiler rather than the buildPlatform one, or cargo links
            # hostPlatform code with the buildPlatform wrapper, which carries
            # none of the hostPlatform's -L paths:
            #
            #   ld.bfd: cannot find -lpam: No such file or directory
            #
            # for a pam that is an ordinary buildInput.
            #
            # Both tables would be named identically in that case, so emitting
            # the block above instead is not an option; the fix is to pick the
            # right compiler here. Unchanged for native builds (the platforms
            # are equal) and for ordinary cross (the config strings differ, so
            # the block above is emitted and this one keeps describing the
            # buildPlatform).
            linkerCc =
              if
                stdenv.hostPlatform.rust.rustcTarget == stdenv.targetPlatform.rust.rustcTarget
                && stdenv.hostPlatform != stdenv.targetPlatform
              then
                pkgsTargetTarget.stdenv.cc
              else
                stdenv.cc;
          in
          ''
            [target."${stdenv.hostPlatform.rust.rustcTarget}"]
            "linker" = "${linkerCc}/bin/${linkerCc.targetPrefix}cc"
            "rustflags" = [ ${
              lib.optionalString (!stdenv.hostPlatform.isx86_32) ''"-Cforce-frame-pointers=yes"''
            } ]
          ''
        );
    };

    passthru.tests = {
      test = tests.rust-hooks.cargoSetupHook;
      ${if stdenv.hostPlatform.isLinux then "testCross" else null} =
        pkgsCross.riscv64.tests.rust-hooks.cargoSetupHook;
    };
    meta.license = lib.licenses.mit;
  } ./cargo-setup-hook.sh;

  maturinBuildHook = makeSetupHook {
    name = "maturin-build-hook.sh";
    propagatedBuildInputs = [
      pkgsHostTarget.maturin
      pkgsHostTarget.cargo
      pkgsHostTarget.rustc
    ];
    substitutions = {
      inherit (stdenv.targetPlatform.rust) rustcTargetSpec;
      inherit (rust.envVars) setEnv;

    };
    meta.license = lib.licenses.mit;
  } ./maturin-build-hook.sh;

  bindgenHook = makeSetupHook {
    name = "rust-bindgen-hook";
    substitutions = {
      libclang = (lib.getLib clang.cc);
      inherit clang;
    };
    meta.license = lib.licenses.mit;
  } ./rust-bindgen-hook.sh;
}
