{
  lib,
  stdenv,
  buildPackages,
  makeSetupHook,
  cargo-tauri,
  rust,
  # The subdirectory of `target/` from which to copy the build artifacts
  targetSubdirectory ? stdenv.hostPlatform.rust.cargoShortTarget,
}:

let
  kernelName = stdenv.hostPlatform.parsed.kernel.name;
in
makeSetupHook {
  name = "tauri-hook";

  # cargo and cargo-tauri are executed during the consumer's build, so they
  # must be BUILD platform tools. Taking them from the calling scope works
  # natively (buildPackages == pkgs) but breaks cross builds reached through
  # the `cargo-tauri.hook` passthru: passthru attributes bypass splicing, so
  # the consumer gets the HOST instantiation of this hook, which would
  # propagate host binaries -- unrunnable on a true-cross builder, and enough
  # to trip cargo's cross-to-x86 meta.broken at evaluation time.
  # cargo-tauri.gst-plugin below is different: a host gstreamer plugin whose
  # path is baked into runtime wrappers, correctly from the host set.
  propagatedBuildInputs = [
    buildPackages.cargo
    buildPackages.cargo-tauri
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    cargo-tauri.gst-plugin
  ];

  substitutions = {
    inherit targetSubdirectory;
    inherit (rust.envVars) rustHostPlatformSpec setEnv;

    # A map of the bundles used for Tauri's different supported platforms
    # https://github.com/tauri-apps/tauri/blob/23a912bb84d7c6088301e1ffc59adfa8a799beab/README.md#platforms
    defaultTauriBundleType =
      {
        darwin = "app";
        linux = "deb";
      }
      .${kernelName} or (throw "${kernelName} is not supported by cargo-tauri.hook");

    fixupScript = lib.optionalString stdenv.hostPlatform.isLinux ''
      gappsWrapperArgs+=(
        --prefix WEBKIT_GST_ALLOWED_URI_PROTOCOLS : "asset"
        # Not picked up automatically by the wrappers from the propagatedBuildInputs.
        --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${cargo-tauri.gst-plugin}/lib/gstreamer-1.0/"
        # fix NVIDIA issues with Tauri
        # https://github.com/tauri-apps/tauri/issues/9394#issuecomment-3795449374
        --set-default __NV_DISABLE_EXPLICIT_SYNC 1
      )
    '';

    # $targetDir is the path to the build artifacts (i.e., `./target/release`)
    installScript =
      {
        darwin = ''
          mkdir -p "$out/Applications"

          shopt -s nullglob
          appBundles=("$targetDir"/bundle/macos/*.app)
          shopt -u nullglob

          if [ "''${#appBundles[@]}" -eq 0 ]; then
            echo "cargo-tauri.hook: no .app bundles found in $targetDir/bundle/macos" >&2
            exit 1
          fi

          mv -- "''${appBundles[@]}" "$out/Applications/"
        '';

        linux = ''
          mkdir -p $out
          mv "$targetDir"/bundle/deb/*/data/usr/* $out/
        '';
      }
      .${kernelName} or (throw "${kernelName} is not supported by cargo-tauri.hook");
  };

  meta = {
    inherit (cargo-tauri.meta) maintainers broken;
    # Platforms that Tauri supports bundles for
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
    license = lib.licenses.mit;
  };
} ./hook.sh
