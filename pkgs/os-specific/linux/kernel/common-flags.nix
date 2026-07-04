{
  lib,
  stdenv,
  buildPackages,
  extraMakeFlags ? [ ],
}:
# Absolute paths for compilers avoid any PATH-clobbering issues.
[
  #
  # We use the unwrapped compiler, because the clang-wrapper doesn't like -target.
  "CC=${lib.getExe stdenv.cc.cc}"
  # The wrapper for ld.lld breaks linking the kernel. We use the unwrapped linker as workaround. See:
  # https://github.com/NixOS/nixpkgs/issues/321667
  "LD=${lib.getExe' stdenv.cc.bintools.bintools "${stdenv.cc.targetPrefix}ld"}"
  "AR=${lib.getExe' stdenv.cc "${stdenv.cc.targetPrefix}ar"}"
  "NM=${lib.getExe' stdenv.cc "${stdenv.cc.targetPrefix}nm"}"
  "STRIP=${lib.getExe' stdenv.cc.bintools.bintools "${stdenv.cc.targetPrefix}strip"}"
  "OBJCOPY=${lib.getExe' stdenv.cc "${stdenv.cc.targetPrefix}objcopy"}"
  "OBJDUMP=${lib.getExe' stdenv.cc "${stdenv.cc.targetPrefix}objdump"}"
  "READELF=${lib.getExe' stdenv.cc "${stdenv.cc.targetPrefix}readelf"}"
  "HOSTCC=${lib.getExe' buildPackages.stdenv.cc "${buildPackages.stdenv.cc.targetPrefix}cc"}"
  "HOSTCXX=${lib.getExe' buildPackages.stdenv.cc "${buildPackages.stdenv.cc.targetPrefix}c++"}"
  "HOSTAR=${lib.getExe' buildPackages.stdenv.cc.bintools "${buildPackages.stdenv.cc.targetPrefix}ar"}"
  "HOSTLD=${lib.getExe' buildPackages.stdenv.cc.bintools "${buildPackages.stdenv.cc.targetPrefix}ld"}"
  # GCC 15 + glibc 2.42 compatibility: glibc headers trigger warnings in
  # kernel host tools (objtool, resolve_btfids/libbpf, genksyms, etc.):
  #   - stdio.h:522 vsscanf / inttypes.h:394 wcstoumax redundant redecls
  #   - sys/cdefs.h:486 __attribute_const__ macro redefinition
  # HOSTCFLAGS=-Wno-error covers tools where our flags appear last (objtool).
  # For libbpf: tools/scripts/Makefile.include puts -Wredundant-decls in
  # EXTRA_WARNINGS, which libbpf appends AFTER EXTRA_CFLAGS=$(HOSTCFLAGS),
  # re-enabling the warning. Passing EXTRA_WARNINGS= on the command line
  # overrides the makefile assignments (GNU Make command-line precedence),
  # preventing the warning from ever being added to libbpf's CFLAGS.
  "HOSTCFLAGS=-Wno-error"
  "EXTRA_WARNINGS="
  "ARCH=${stdenv.hostPlatform.linuxArch}"
  "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
]
# Add the built in headers the kernel needs
++ lib.optionals (stdenv.cc.isClang) (
  let
    clangLib = lib.getLib stdenv.cc.cc;
    majorVer = lib.versions.major clangLib.version;
  in
  [
    "CFLAGS_MODULE=-I${clangLib}/lib/clang/${majorVer}/include"
    "CFLAGS_KERNEL=-I${clangLib}/lib/clang/${majorVer}/include"
  ]
)
++ extraMakeFlags
