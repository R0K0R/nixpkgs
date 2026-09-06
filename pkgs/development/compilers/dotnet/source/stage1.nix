{
  callPackage,
  buildPackages,

  releaseManifestFile,
  tarballHash,
  depsFile,
  bootstrapSdk,
}:

let
  mkVMR = callPackage ./vmr.nix;

  # stage0 exists only to produce an SDK that is EXECUTED during this build;
  # none of its output is shipped. Instantiate it from the build-platform
  # package set, so that SDK is built to run on the machine doing the
  # building rather than on the machine the result targets. callPackage hands
  # a package its own scope's callPackage, so this cascades: stage0.nix's
  # `mkVMR = callPackage ./vmr.nix` and its `mkPackages` both become
  # build-platform without either file changing.
  #
  # Only the data arguments are forwarded, deliberately. Splatting stage1's
  # own `@args` here would pass stage1's host-scope stdenv/lib/callPackage in
  # explicitly, and callPackageWith resolves `autoArgs // args` -- explicit
  # args win -- so stage0 would receive the HOST callPackage back and rebuild
  # a host-platform VMR, silently reinstating the bug.
  stage0 = buildPackages.callPackage ./stage0.nix {
    inherit
      releaseManifestFile
      tarballHash
      depsFile
      bootstrapSdk
      ;
    baseName = "dotnet-stage0";
  };

in
(mkVMR {
  inherit releaseManifestFile tarballHash;
  bootstrapSdk = stage0.sdk;
  hasRuntime = true;
}).overrideAttrs
  (old: {
    passthru = old.passthru or { } // {
      inherit stage0;
      inherit (stage0.vmr) fetch-drv fetch-deps;
    };
  })
