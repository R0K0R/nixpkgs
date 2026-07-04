{
  lib,
  fetchFromGitHub,
  runCommand,
  stdenv,
  clang_20,
  buildNpmPackage,
  docify,
  testers,
  writeText,
  jq,
  basedpyright,
  pkg-config,
  libsecret,
  nix-update-script,
  versionCheckHook,
}:

buildNpmPackage rec {
  pname = "basedpyright";
  version = "1.39.8";

  src = fetchFromGitHub {
    owner = "detachhead";
    repo = "basedpyright";
    tag = "v${version}";
    hash = "sha256-8S83CTd/td7USKxfCI0cXd2gPBMivi4QMRQwVgxhs6w=";
  };

  npmDepsHash = "sha256-humpJB+fv3+PITcPCz3uY2jNANb3P7sXy0lFP8Eg58I=";
  npmWorkspace = "packages/pyright";

  # npmConfigHook runs `npm rebuild` in postPatchHooks, before preBuild. In
  # cross builds the keytar native addon's node-gyp build fails because it
  # can't find the prefixed cross pkg-config. keytar's credential-storage
  # backend isn't needed for the LSP core, so skip all install scripts during
  # rebuild in cross builds rather than fixing node-gyp's pkg-config lookup.
  npmRebuildFlags = lib.optionals (stdenv.buildPlatform != stdenv.hostPlatform) [ "--ignore-scripts" ];

  preBuild = ''
    # Build the docstubs
    cp -r packages/pyright-internal/typeshed-fallback docstubs
    docify docstubs/stdlib --builtins-only --in-place
  '';

  nativeBuildInputs = [
    docify
    pkg-config
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin clang_20; # clang_21 breaks keytar

  buildInputs = [ libsecret ];

  postInstall = ''
    mv "$out/bin/pyright" "$out/bin/basedpyright"
    mv "$out/bin/pyright-langserver" "$out/bin/basedpyright-langserver"
    # Remove dangling symlinks created during installation (remove -delete to just see the files, or -print '%l\n' to see the target
    find -L $out -type l -print -delete
    # Remove native module build artifacts that reference nodejs source
    rm -rf "$out/lib/node_modules/pyright-root/node_modules/keytar/build"
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    updateScript = nix-update-script { };
    tests = {
      # We are expecting 4 errors. Any other amount would indicate not working
      # stub files, for instance.
      simple = testers.testEqualContents {
        assertion = "simple type checking";
        expected = writeText "expected" ''
          4
        '';
        actual =
          runCommand "actual"
            {
              nativeBuildInputs = [
                jq
                basedpyright
              ];
              base = writeText "test.py" ''
                import sys
                from time import tzset

                def print_string(a_string: str):
                    a_string += 42
                    print(a_string)

                if sys.platform == "win32":
                    print_string(69)
                    this_function_does_not_exist("nice!")
                else:
                    result_of_tzset_is_None: str = tzset()
              '';
              configFile = writeText "pyproject.toml" ''
                [tool.pyright]
                typeCheckingMode = "strict"
              '';
            }
            ''
              (basedpyright --outputjson $base || true) | jq -r .summary.errorCount > $out
            '';
      };
    };
  };

  meta = {
    changelog = "https://github.com/detachhead/basedpyright/releases/tag/${src.tag}";
    description = "Type checker for the Python language";
    homepage = "https://github.com/detachhead/basedpyright";
    license = lib.licenses.mit;
    mainProgram = "basedpyright";
    maintainers = with lib.maintainers; [
      kiike
      misilelab
    ];
  };
}
