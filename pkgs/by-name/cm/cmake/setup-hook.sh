addCMakeParams() {
    # NIXPKGS_CMAKE_PREFIX_PATH is like CMAKE_PREFIX_PATH except cmake
    # will not search it for programs
    addToSearchPath NIXPKGS_CMAKE_PREFIX_PATH $1
}

cmakeConfigurePhase() {
    runHook preConfigure

    # default to CMake defaults if unset
    : ${cmakeBuildDir:=build}

    export CTEST_OUTPUT_ON_FAILURE=1
    if [ -n "${enableParallelChecking-1}" ]; then
        export CTEST_PARALLEL_LEVEL=$NIX_BUILD_CORES
    fi

    if [ -z "${dontUseCmakeBuildDir-}" ]; then
        mkdir -p "$cmakeBuildDir"
        cd "$cmakeBuildDir"
        : ${cmakeDir:=..}
    else
        : ${cmakeDir:=.}
    fi

    if [ -z "${dontAddPrefix-}" ]; then
        prependToVar cmakeFlags "-DCMAKE_INSTALL_PREFIX=$prefix"
    fi

    # We should set the proper `CMAKE_SYSTEM_NAME`.
    # http://www.cmake.org/Wiki/CMake_Cross_Compiling
    #
    # Unfortunately cmake seems to expect absolute paths for ar, ranlib, and
    # strip. Otherwise they are taken to be relative to the source root of the
    # package being built.
    prependToVar cmakeFlags "-DCMAKE_CXX_COMPILER=$CXX"
    prependToVar cmakeFlags "-DCMAKE_C_COMPILER=$CC"
    prependToVar cmakeFlags "-DCMAKE_AR=$(command -v $AR)"
    prependToVar cmakeFlags "-DCMAKE_RANLIB=$(command -v $RANLIB)"
    prependToVar cmakeFlags "-DCMAKE_STRIP=$(command -v $STRIP)"

    # This installs shared libraries with a fully-specified install
    # name. By default, cmake installs shared libraries with just the
    # basename as the install name, which means that, on Darwin, they
    # can only be found by an executable at runtime if the shared
    # libraries are in a system path or in the same directory as the
    # executable. This flag makes the shared library accessible from its
    # nix/store directory.
    prependToVar cmakeFlags "-DCMAKE_INSTALL_NAME_DIR=${!outputLib}/lib"

    # The docdir flag needs to include PROJECT_NAME as per GNU guidelines,
    # try to extract it from CMakeLists.txt.
    if [[ -z "$shareDocName" ]]; then
        local cmakeLists="${cmakeDir}/CMakeLists.txt"
        if [[ -f "$cmakeLists" ]]; then
            local shareDocName="$(grep --only-matching --perl-regexp --ignore-case '\bproject\s*\(\s*"?\K([^[:space:]")]+)' < "$cmakeLists" | head -n1)"
        fi
        # The argument sometimes contains garbage or variable interpolation.
        # When that is the case, let’s fall back to the derivation name.
        if [[ -z "$shareDocName" ]] || echo "$shareDocName" | grep -q '[^a-zA-Z0-9_+-]'; then
            if [[ -n "${pname-}" ]]; then
                shareDocName="$pname"
            else
                shareDocName="$(echo "$name" | sed 's/-[^a-zA-Z].*//')"
            fi
        fi
    fi

    # This ensures correct paths with multiple output derivations
    # It requires the project to use variables from GNUInstallDirs module
    # https://cmake.org/cmake/help/latest/module/GNUInstallDirs.html
    prependToVar cmakeFlags "-DCMAKE_INSTALL_BINDIR=${!outputBin}/bin"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_SBINDIR=${!outputBin}/sbin"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_INCLUDEDIR=${!outputInclude}/include"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_MANDIR=${!outputMan}/share/man"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_INFODIR=${!outputInfo}/share/info"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_DOCDIR=${!outputDoc}/share/doc/${shareDocName}"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_LIBDIR=${!outputLib}/lib"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_LIBEXECDIR=${!outputLib}/libexec"
    prependToVar cmakeFlags "-DCMAKE_INSTALL_LOCALEDIR=${!outputLib}/share/locale"

    # Don’t build tests when doCheck = false
    if [ -z "${doCheck-}" ]; then
        prependToVar cmakeFlags "-DBUILD_TESTING=OFF"
    fi

    # Always build Release, to ensure optimisation flags
    prependToVar cmakeFlags "-DCMAKE_BUILD_TYPE=${cmakeBuildType:-Release}"

    # Disable user package registry to avoid potential side effects
    # and unecessary attempts to access non-existent home folder
    # https://cmake.org/cmake/help/latest/manual/cmake-packages.7.html#disabling-the-package-registry
    prependToVar cmakeFlags "-DCMAKE_EXPORT_NO_PACKAGE_REGISTRY=ON"
    prependToVar cmakeFlags "-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF"
    prependToVar cmakeFlags "-DCMAKE_FIND_USE_SYSTEM_PACKAGE_REGISTRY=OFF"

    if [ "${buildPhase-}" = ninjaBuildPhase ]; then
        prependToVar cmakeFlags "-GNinja"
    fi

    local flagsArray=()
    concatTo flagsArray cmakeFlags cmakeFlagsArray

    # F11: Generate CMAKE_PROJECT_INCLUDE preload forwarding all -D flags as
    # forced CACHE entries so ExternalProject_Add/FetchContent sub-builds inherit
    # the cross flags from the outer cmake invocation. Pattern B2.
    # F14: Also append try_run cache-answer vars so cmake try_run() probes that
    # would exec a HOST binary on BUILD can be answered statically. Pattern 63.
    local _nixpkgsPreload="$TMPDIR/nixpkgs-cmake-preload.cmake"
    : > "$_nixpkgsPreload"
    local _f _k _v
    for _f in "${flagsArray[@]}"; do
        case "$_f" in
            -D*=*)
                _k="${_f#-D}"; _k="${_k%%=*}"
                _v="${_f#-D*=}"
                [ "$_k" != "CMAKE_PROJECT_INCLUDE" ] && \
                    printf 'set(%s "%s" CACHE STRING "" FORCE)\n' "$_k" "$_v" >> "$_nixpkgsPreload"
                ;;
        esac
    done
    if [ -n "${cmakeTryRunCacheVars-}" ]; then
        local _e
        for _e in $cmakeTryRunCacheVars; do
            _k="${_e%%=*}"; _v="${_e#*=}"
            printf 'set(%s "%s" CACHE STRING "" FORCE)\n' "$_k" "$_v" >> "$_nixpkgsPreload"
        done
    fi
    [ -f "${cmakeDir}/cmake-try-run-cache.cmake" ] && \
        cat "${cmakeDir}/cmake-try-run-cache.cmake" >> "$_nixpkgsPreload"
    [ -s "$_nixpkgsPreload" ] && \
        flagsArray=("-DCMAKE_PROJECT_INCLUDE=$_nixpkgsPreload" "${flagsArray[@]}")

    echoCmd 'cmake flags' "${flagsArray[@]}"

    cmake "$cmakeDir" "${flagsArray[@]}"

    if ! [[ -v enableParallelBuilding ]]; then
        enableParallelBuilding=1
        echo "cmake: enabled parallel building"
    fi
    if [[ "$enableParallelBuilding" -ne 0 ]]; then
        export CMAKE_BUILD_PARALLEL_LEVEL=$NIX_BUILD_CORES
    fi

    if ! [[ -v enableParallelInstalling ]]; then
        enableParallelInstalling=1
        echo "cmake: enabled parallel installing"
    fi

    runHook postConfigure
}

if [ -z "${dontUseCmakeConfigure-}" -a -z "${configurePhase-}" ]; then
    setOutputFlags=
    configurePhase=cmakeConfigurePhase
fi

addEnvHooks "$targetOffset" addCMakeParams

makeCmakeFindLibs() {
    isystem_seen=
    iframework_seen=
    for flag in ${NIX_CFLAGS_COMPILE-} ${NIX_LDFLAGS-}; do
        if test -n "$isystem_seen" && test -d "$flag"; then
            isystem_seen=
            addToSearchPath CMAKE_INCLUDE_PATH "${flag}"
        elif test -n "$iframework_seen" && test -d "$flag"; then
            iframework_seen=
            addToSearchPath CMAKE_FRAMEWORK_PATH "${flag}"
        else
            isystem_seen=
            iframework_seen=
            case $flag in
            -I*)
                addToSearchPath CMAKE_INCLUDE_PATH "${flag:2}"
                ;;
            -L*)
                addToSearchPath CMAKE_LIBRARY_PATH "${flag:2}"
                ;;
            -F*)
                addToSearchPath CMAKE_FRAMEWORK_PATH "${flag:2}"
                ;;
            -isystem)
                isystem_seen=1
                ;;
            -iframework)
                iframework_seen=1
                ;;
            esac
        fi
    done
}

# not using setupHook, because it could be a setupHook adding additional
# include flags to NIX_CFLAGS_COMPILE
postHooks+=(makeCmakeFindLibs)

# F5: Populate CMAKE_PROGRAM_PATH from nativeBuildInputs bin/ dirs.
# cmake's find_program() searches PATH and CMAKE_PROGRAM_PATH but NOT
# NIXPKGS_CMAKE_PREFIX_PATH. Without this, find_program(TOOL) returns NOTFOUND
# even when TOOL is in nativeBuildInputs. Pattern E binary-discovery side.
addCMakeProgramPath() {
    if [ -d "$1/bin" ]; then addToSearchPath CMAKE_PROGRAM_PATH "$1/bin"; fi
}
addEnvHooks "$targetOffset" addCMakeProgramPath

# F12: Read cmake-cross-helper-flags from HOST buildInputs and prepend to
# cmakeFlags. Packages write BUILD-platform cmake tool vars (Qt6*Tools_DIR,
# KF6_HOST_TOOLING, etc.) to nix-support/cmake-cross-helper-flags in their
# postInstall; this hook forwards them into every consumer automatically.
# Flags are also forwarded into ExternalProject_Add sub-builds via the F11
# preload above. Pattern B/G5.
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
