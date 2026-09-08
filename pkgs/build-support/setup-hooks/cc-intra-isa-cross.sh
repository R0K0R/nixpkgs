# Keep this stdenv's own cc-wrapper ahead of the build platform's toolchain on
# PATH, for intra-ISA cross builds.
#
# THE PROBLEM
# -----------
# In an intra-ISA cross build the host and build platforms share a config
# triple, so `<triple>-gcc` is ambiguous: both toolchains provide it. A package
# that pulls the build platform's compiler in explicitly --
#
#     depsBuildBuild = [ buildPackages.stdenv.cc ];
#
# -- gets those directories at the FRONT of PATH, ahead of its own stdenv's
# cc-wrapper, and one of them is the UNWRAPPED gcc. Measured on
# curl-impersonate: PATH position 1 was the build gcc-wrapper and position 2 the
# raw gcc, so `<triple>-gcc` resolved to a compiler with none of the wrapper's
# -B and -L injection. It then drove its own configured ld.bfd and the link died
# on "cannot find Scrt1.o", "cannot find crti.o", "cannot find -lgcc_s".
#
# A genuine cross build never hits this: the triples differ, so the prefixed
# name is unambiguous and the build platform's compiler answers to a different
# one. It is specific to sharing the triple.
#
# WHY A LATE HOOK RATHER THAN AN EDIT TO setup.sh
# -----------------------------------------------
# setup.sh is copied verbatim into every derivation, so editing it re-hashes
# the whole tree including native builds that can never reach the new code --
# the exact regression "stdenv, cc/bintools/pkg-config-wrapper, cmake: confine
# intra-ISA cross changes" had to undo. Injected via the cross stdenv's
# extraNativeBuildInputs instead, like the cmake hook beside it.
#
# WHY postHooks AND NOT THE HOOK BODY
# -----------------------------------
# Doing the prepend here at source time does not work: setup hooks are sourced
# DURING _activatePkgs, and depsBuildBuild's directories are prepended after
# that, landing in front again (measured -- the same prepend as a plain setup
# hook still lost the lookup). `runHook postHook` fires after _activatePkgs and
# before any phase, so a function registered there wins and still precedes a
# package's own preConfigure.
_intraIsaPreferOwnCC() {
    if [ -n "${NIX_CC:-}" ] && [ -d "$NIX_CC/bin" ]; then
        PATH="$NIX_CC/bin${PATH:+:}$PATH"
        export PATH
    fi
}

postHooks+=(_intraIsaPreferOwnCC)
