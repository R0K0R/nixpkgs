# cmake fixes for intra-ISA cross builds.
#
# WHY THIS IS A SEPARATE HOOK RATHER THAN EDITS TO cmake's setup-hook.sh
# ---------------------------------------------------------------------
# cmake is a nativeBuildInput: the cmake that runs during a cross build is the
# BUILD-platform one. So these fixes cannot be gated on "is cmake itself cross"
# -- the executing cmake is always native. Editing pkgs/by-name/cm/cmake/
# setup-hook.sh instead makes the change unconditional, which changes cmake's
# hash and therefore every package built with cmake (brotli, zstd, curl, KDE,
# Qt, ...) even on plain native builds that can never need any of it. Measured:
# that single file was what kept `curl` diverging from cache.nixos.org after the
# whole stdenv/wrapper layer had been made byte-identical to upstream.
#
# Injected via the cross stdenv's extraNativeBuildInputs when isIntraISACross --
# the same mechanism pkgs/stdenv/cross/default.nix already uses for patchelf,
# and pkgs/stdenv/darwin/default.nix for its aarch64-only hooks. cmake itself
# stays pristine and Hydra-cached.
#
# Everything here is gated on cmake actually being in use, since
# extraNativeBuildInputs puts this hook in EVERY derivation.

_cmakeIntraIsaInUse() {
    declare -F cmakeConfigurePhase > /dev/null
}

# 1. CMAKE_PROJECT_INCLUDE preload
#
# ExternalProject_Add/FetchContent sub-builds run their own cmake configure and
# ignore the outer flagsArray, so they re-detect the toolchain and get the
# native one instead of the cross one. Forward the outer -D flags into a preload
# file as forced CACHE entries.
#
# Runs in preConfigure rather than mid-phase (where the original lived). That is
# equivalent: cmakeConfigurePhase builds flagsArray purely as
# `concatTo flagsArray cmakeFlags cmakeFlagsArray`, and every flag the phase
# itself adds goes through `prependToVar cmakeFlags` and is in the exclusion
# list below (the install dirs, the compiler/ar/ranlib/strip vars, BUILD_TESTING,
# CMAKE_BUILD_TYPE, the registry vars). `-GNinja` is not -D*=* so the case skips
# it. The non-excluded set is therefore identical seen from here.
_cmakeIntraIsaPreload() {
    _cmakeIntraIsaInUse || return 0

    local _preload="$TMPDIR/nixpkgs-cmake-preload.cmake"
    : > "$_preload"

    local _f _k _v
    for _f in ${cmakeFlags-} ${cmakeFlagsArray+"${cmakeFlagsArray[@]}"}; do
        case "$_f" in
            -D*=*)
                _k="${_f#-D}"; _k="${_k%%=*}"
                _v="${_f#-D*=}"
                case "$_k" in
                    CMAKE_PROJECT_INCLUDE|\
                    CMAKE_C_COMPILER|CMAKE_CXX_COMPILER|\
                    CMAKE_AR|CMAKE_RANLIB|CMAKE_STRIP|\
                    CMAKE_INSTALL_PREFIX|CMAKE_INSTALL_NAME_DIR|\
                    CMAKE_INSTALL_BINDIR|CMAKE_INSTALL_SBINDIR|\
                    CMAKE_INSTALL_INCLUDEDIR|CMAKE_INSTALL_MANDIR|\
                    CMAKE_INSTALL_INFODIR|CMAKE_INSTALL_DOCDIR|\
                    CMAKE_INSTALL_LIBDIR|CMAKE_INSTALL_LIBEXECDIR|\
                    CMAKE_INSTALL_LOCALEDIR|\
                    CMAKE_FIND_USE_PACKAGE_REGISTRY|\
                    CMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY|\
                    CMAKE_EXPORT_NO_PACKAGE_REGISTRY|\
                    CMAKE_BUILD_TYPE|BUILD_TESTING)
                        : ;;
                    *)
                        printf 'set(%s "%s" CACHE STRING "" FORCE)\n' "$_k" "$_v" >> "$_preload"
                        ;;
                esac
                ;;
        esac
    done

    # cmakeTryRunCacheVars lets a package statically answer specific
    # try_run()/check_c_source_runs() probes ("VAR=value") instead of letting
    # cmake compile-and-execute the check -- which in a cross build would try to
    # run a HOST binary on the BUILD machine.
    if [ -n "${cmakeTryRunCacheVars-}" ]; then
        local _e
        for _e in $cmakeTryRunCacheVars; do
            _k="${_e%%=*}"; _v="${_e#*=}"
            printf 'set(%s "%s" CACHE STRING "" FORCE)\n' "$_k" "$_v" >> "$_preload"
        done
    fi

    # NOTE: the original ran after cmakeConfigurePhase had cd'd into
    # $cmakeBuildDir and defaulted cmakeDir to "..". Here we are still in the
    # source root, so "." is the equivalent. A package that sets cmakeDir
    # explicitly is honoured, but its value is interpreted relative to the
    # source root rather than the build dir.
    if [ -f "${cmakeDir:-.}/cmake-try-run-cache.cmake" ]; then
        cat "${cmakeDir:-.}/cmake-try-run-cache.cmake" >> "$_preload"
    fi

    if [ -s "$_preload" ]; then
        cmakeFlagsArray=("-DCMAKE_PROJECT_INCLUDE=$_preload" ${cmakeFlagsArray+"${cmakeFlagsArray[@]}"})
    fi
}

# 2. Strip the redundant glibc -isystem cmake's cross-compiler probe injects.
#
# cmake runs `$CXX -v -E /dev/null`, harvests the implicit include dirs and
# re-emits them as explicit -isystem flags in the generated build files. That
# puts glibc-dev ahead of the C++ stdlib headers, breaking #include_next
# <stdlib.h> inside <cstdlib>. The wrapper already injects the correct order via
# NIX_CFLAGS_COMPILE, so cmake's -isystem is redundant and actively harmful.
#
# The original ran at the end of cmakeConfigurePhase, immediately before
# `runHook postConfigure`; running as postConfigure is equivalent, since the
# generated *.ninja / flags.make already exist and nothing reads them between.
_cmakeIntraIsaStripIsystem() {
    _cmakeIntraIsaInUse || return 0

    find . \( -name '*.ninja' -o -name 'flags.make' \) \
        | xargs -r sed -Ei \
            's| -isystem /nix/store/[a-z0-9]{32}-glibc-[^ ]*/include||g'
}

preConfigureHooks+=(_cmakeIntraIsaPreload)
postConfigureHooks+=(_cmakeIntraIsaStripIsystem)

# 3. find_package() should also see nativeBuildInputs' cmake configs (ECM,
# wayland-scanner). cmake's own addCMakeParams fires at $targetOffset (HOST
# buildInputs) only.
addCMakeNativePrefixPath() {
    addToSearchPath NIXPKGS_CMAKE_PREFIX_PATH "$1"
}
addEnvHooks "$hostOffset" addCMakeNativePrefixPath

# 4. Let a package publish cross-specific cmake flags via
# nix-support/cmake-cross-helper-flags and have every downstream consumer
# forward them, without each consumer knowing the flag.
addCMakeCrossHelperFlags() {
    local _pkg="$1"
    if [ -f "$_pkg/nix-support/cmake-cross-helper-flags" ]; then
        local _flag
        while IFS= read -r _flag || [ -n "$_flag" ]; do
            if [ -n "$_flag" ]; then prependToVar cmakeFlags "$_flag"; fi
        done < "$_pkg/nix-support/cmake-cross-helper-flags"
    fi
}
addEnvHooks "$hostOffset" addCMakeCrossHelperFlags

# 5. find_program() searches PATH and CMAKE_PROGRAM_PATH but not
# NIXPKGS_CMAKE_PREFIX_PATH, so a tool present only as a nativeBuildInput came
# back NOTFOUND unless it also happened to be on PATH.
addCMakeProgramPath() {
    if [ -d "$1/bin" ]; then addToSearchPath CMAKE_PROGRAM_PATH "$1/bin"; fi
}
addEnvHooks "$targetOffset" addCMakeProgramPath
