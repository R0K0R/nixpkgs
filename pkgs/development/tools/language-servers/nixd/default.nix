{
  lib,
  stdenv,
  buildPackages,
  fetchFromGitHub,
  versionCheckHook,
  boost,
  gtest,
  llvmPackages,
  meson,
  mesonEmulatorHook,
  ninja,
  nixVersions,
  nix-update-script,
  nixd,
  nixf,
  nixt,
  nlohmann_json,
  pkg-config,
  testers,
  python3,
  libxml2,
  zlib,
}:

let
  nixComponents = nixVersions.latest.libs;
  common = rec {
    version = "2.9.3";

    src = fetchFromGitHub {
      owner = "nix-community";
      repo = "nixd";
      tag = version;
      hash = "sha256-ud2XcAxUUYenNrGyrh4B9LrDcMZ6eJfPkL60lDcanDI=";
    };

    nativeBuildInputs = [
      meson
      ninja
      python3
      pkg-config
    ];

    mesonBuildType = "release";

    __structuredAttrs = true;
    strictDeps = true;
    separateDebugInfo = true;

    doCheck = true;

    meta = {
      homepage = "https://github.com/nix-community/nixd";
      changelog = "https://github.com/nix-community/nixd/releases/tag/${version}";
      license = lib.licenses.lgpl3Plus;
      maintainers = with lib.maintainers; [
        inclyc
        Ruixi-rebirth
        aleksana
      ];
      platforms = lib.platforms.unix;
    };
  };
in
{
  nixf = stdenv.mkDerivation (
    common
    // {
      pname = "nixf";

      sourceRoot = "${common.src.name}/libnixf";

      outputs = [
        "out"
        "dev"
      ];

      nativeBuildInputs =
        common.nativeBuildInputs
        ++ lib.optionals (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) [ mesonEmulatorHook ];

      buildInputs = [
        nixComponents.nix-expr
        gtest
        boost
        nlohmann_json
      ];

      passthru.tests.pkg-config = testers.testMetaPkgConfig nixf;

      # PrimOpsInfo.cpp is the output of a program linked against nix-expr. When this
      # platform can't run the host's binaries, it is generated with the build platform's
      # nix-expr instead: the primop table doesn't depend on the CPU, and an emulator
      # need not implement every host instruction (qemu's TCG has no GFNI, which gcc
      # emits for -march=meteorlake, e.g. in Boost.URL).
      passthru.primOpsInfo = buildPackages.callPackage (
        {
          stdenv,
          pkg-config,
          nixVersions,
        }:
        stdenv.mkDerivation {
          pname = "nixf-primops-info";
          inherit (common) version src;
          sourceRoot = "${common.src.name}/libnixf/src";
          strictDeps = true;
          nativeBuildInputs = [ pkg-config ];
          buildInputs = [ nixVersions.latest.libs.nix-expr ];
          buildPhase = ''
            runHook preBuild
            $CXX -std=gnu++20 Basic/PrimOpsInfoGen.cpp -o PrimOpsInfoGen $(pkg-config --cflags --libs nix-expr)
            ./PrimOpsInfoGen PrimOpsInfo.cpp
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            cp PrimOpsInfo.cpp $out
            runHook postInstall
          '';
        }
      ) { };

      meta = common.meta // {
        description = "Nix language frontend, parser & semantic analysis";
        mainProgram = "nixf-tidy";
        pkgConfigModules = [ "nixf" ];
      };
    }
    // lib.optionalAttrs (!stdenv.buildPlatform.canExecute stdenv.hostPlatform) {
      postPatch = ''
        substituteInPlace src/meson.build \
          --replace-fail "command: [ prim_ops_info_gen,  '@OUTPUT@' ]," \
                         "command: [ 'cp', '${nixf.primOpsInfo}', '@OUTPUT@' ],"
      '';
    }
  );

  nixt = stdenv.mkDerivation (
    common
    // {
      pname = "nixt";

      sourceRoot = "${common.src.name}/libnixt";

      outputs = [
        "out"
        "dev"
      ];

      buildInputs = [
        nixComponents.nix-main
        nixComponents.nix-expr
        nixComponents.nix-cmd
        nixComponents.nix-flake
        gtest
        boost
      ];

      passthru.tests.pkg-config = testers.testMetaPkgConfig nixt;

      meta = common.meta // {
        description = "Supporting library that wraps C++ nix";
        pkgConfigModules = [ "nixt" ];
      };
    }
  );

  nixd = stdenv.mkDerivation (
    common
    // {
      pname = "nixd";

      sourceRoot = "${common.src.name}/nixd";

      buildInputs = [
        nixComponents.nix-main
        nixComponents.nix-expr
        nixComponents.nix-cmd
        nixComponents.nix-flake
        nixf
        nixt
        llvmPackages.llvm
        gtest
        boost
        libxml2
        zlib
      ];

      nativeBuildInputs = common.nativeBuildInputs ++ [
        # Meson can use either llvm-config (which lives in libllvm.dev) or CMake to find LLVM
        # Since finding LLVM via CMake is more fragile, prefer llvm-config
        (lib.getDev llvmPackages.libllvm)
      ];

      # Required when cross compiling to make Meson find llvm-config-native
      preConfigure = lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
        export PATH="${lib.getDev llvmPackages.llvm}/bin:$PATH"
      '';

      disallowedRequisites = [ (lib.getLib llvmPackages.llvm) ];

      # See https://github.com/nix-community/nixd/issues/519
      doCheck = false;

      doInstallCheck = true;
      nativeInstallCheckInputs = [ versionCheckHook ];

      passthru = {
        updateScript = nix-update-script { };
        tests.version = testers.testVersion { package = nixd; };
      };

      meta = common.meta // {
        description = "Feature-rich Nix language server interoperating with C++ nix";
        mainProgram = "nixd";
      };
    }
  );
}
