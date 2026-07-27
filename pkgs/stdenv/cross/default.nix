{
  lib,
  localSystem,
  crossSystem,
  config,
  overlays,
  crossOverlays,
}:

let
  bootStages = import ../. {
    inherit lib localSystem overlays;

    crossSystem = localSystem;
    crossOverlays = [ ];

    # Ignore custom stdenvs when cross compiling for compatibility
    # Use replaceCrossStdenv instead.
    config = removeAttrs config [ "replaceStdenv" ];
  };

in
lib.init bootStages
++ [

  # Regular native packages
  (
    somePrevStage:
    lib.last bootStages somePrevStage
    // {
      # It's OK to change the built-time dependencies
      allowCustomOverrides = true;
    }
  )

  # Build tool Packages
  (vanillaPackages: {
    inherit config overlays;
    selfBuild = false;
    stdenv =
      assert vanillaPackages.stdenv.buildPlatform == localSystem;
      assert vanillaPackages.stdenv.hostPlatform == localSystem;
      assert vanillaPackages.stdenv.targetPlatform == localSystem;
      vanillaPackages.stdenv.override { targetPlatform = crossSystem; };
    # It's OK to change the built-time dependencies
    allowCustomOverrides = true;
  })

  # Run Packages
  (
    buildPackages:
    let
      adaptStdenv = if crossSystem.isStatic then buildPackages.stdenvAdapters.makeStatic else lib.id;
      stdenvNoCC = adaptStdenv (
        buildPackages.stdenv.override (old: rec {
          buildPlatform = localSystem;
          hostPlatform = crossSystem;
          targetPlatform = crossSystem;

          # Prior overrides are surely not valid as packages built with this run on
          # a different platform, and so are disabled.
          overrides = _: _: { };
          extraBuildInputs = [ ]; # Old ones run on wrong platform
          allowedRequisites = null;

          cc = null;
          hasCC = false;

          /*
            Intra-ISA cross (hostPlatform.config == buildPlatform.config, but the
            platforms differ -- e.g. only in gcc.arch): relax the strictDeps gate
            in setup.sh's _addToEnv so HOST buildInputs' setup hooks still run.
            The ABI hazards strictDeps guards against (wrong rpaths, wrong
            sonames) cannot arise when BUILD and HOST share a config string, and
            those hooks are what populate QMAKEPATH,
            QT_ADDITIONAL_PACKAGES_PREFIX_PATH and friends. Binary executability
            is not assumed: the two platforms still differ in ISA extensions.

            Supplied through the stdenv's own `setupScript` parameter -- the
            extension point `stdenvAdapters.overrideSetup` is built on -- rather
            than by editing pkgs/stdenv/generic/setup.sh. That file is copied
            verbatim into every derivation's stdenv, so a single edited byte
            there changes every hash in the tree, including plain native builds
            that can never reach this branch, forcing a full rebuild and costing
            binary-cache substitutability for all of them. Splicing here confines
            the change to stdenvs that actually are intra-ISA cross, so the patch
            is a no-op for every existing configuration.
          */
          setupScript =
            let
              isIntraISACross = hostPlatform != buildPlatform && hostPlatform.config == buildPlatform.config;
              baseScript = old.setupScript or ../generic/setup.sh;
              anchor = ''            if [[ -z "''${strictDeps-}" ]]; then'';
              replacement = ''            # Intra-ISA cross: also run HOST buildInputs' setup hooks. See the
            # setupScript comment in pkgs/stdenv/cross/default.nix.
            # NIX_IS_INTRA_ISA_CROSS is set by make-derivation.nix.
            if [[ -z "''${strictDeps-}" || "''${NIX_IS_INTRA_ISA_CROSS-}" == "1" ]]; then'';
              base = builtins.readFile baseScript;
              patched = builtins.replaceStrings [ anchor ] [ replacement ] base;
            in
            if !isIntraISACross then
              baseScript
            else if patched == base then
              throw "stdenv/cross: intra-ISA setup.sh splice found no anchor (setup.sh reformatted?)"
            else
              builtins.toFile "setup.sh" patched;

          extraNativeBuildInputs =
            old.extraNativeBuildInputs
            ++ lib.optionals (hostPlatform.isLinux && !buildPlatform.isLinux) [ buildPackages.patchelf ]
            ++ lib.optional (
              let
                f =
                  p:
                  !p.isx86
                  || builtins.elem p.libc [
                    "musl"
                    "wasilibc"
                    "relibc"
                  ]
                  || p.isiOS
                  || p.isGenode;
              in
              f hostPlatform && !(f buildPlatform)
            ) buildPackages.updateAutotoolsGnuConfigScriptsHook
            ++ lib.optional (
              hostPlatform.isCygwin && !buildPlatform.isCygwin
            ) buildPackages.cygwin.cygwinDllLinkHook;
        })
      );
    in
    {
      inherit config;
      overlays = overlays ++ crossOverlays;
      selfBuild = false;
      inherit stdenvNoCC;
      stdenv =
        let
          inherit (stdenvNoCC) hostPlatform targetPlatform;
          baseStdenv = stdenvNoCC.override {
            # Old ones run on wrong platform
            extraBuildInputs = lib.optionals hostPlatform.isDarwin [
              buildPackages.targetPackages.apple-sdk
            ];

            hasCC = !stdenvNoCC.targetPlatform.isGhcjs;

            cc =
              if crossSystem.useiOSPrebuilt or false then
                buildPackages.darwin.iosSdkPkgs.clang
              else if crossSystem.useAndroidPrebuilt or false then
                buildPackages."androidndkPkgs_${crossSystem.androidNdkVersion}".clang
              else if
                targetPlatform.isGhcjs
              # Need to use `throw` so tryEval for splicing works, ugh.  Using
              # `null` or skipping the attribute would cause an eval failure
              # `tryEval` wouldn't catch, wrecking accessing previous stages
              # when there is a C compiler and everything should be fine.
              then
                throw "no C compiler provided for this platform"
              else if crossSystem.isDarwin then
                buildPackages.llvmPackages.systemLibcxxClang
              else if crossSystem.useLLVM or false then
                buildPackages.llvmPackages.clang
              else if crossSystem.useZig or false then
                buildPackages.zig.cc
              else if crossSystem.useArocc or false then
                buildPackages.arocc
              else
                buildPackages.gcc;

          };
        in
        if config ? replaceCrossStdenv then
          config.replaceCrossStdenv { inherit buildPackages baseStdenv; }
        else
          baseStdenv;
    }
  )

]
