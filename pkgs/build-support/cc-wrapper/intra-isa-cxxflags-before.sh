# NIX_CXXFLAGS_COMPILE_BEFORE is like NIX_CFLAGS_COMPILE_BEFORE but applies to
# C++ compilation only. Useful for flags that must precede other -isystem
# entries (e.g. forcing a specific C++ standard library include order) but
# would break plain C compilation if applied unconditionally.
#
# Spliced into cc-wrapper.sh only for cross wrappers -- see the `wrapper` attr
# in default.nix. Its only setter is qtbase, which gates on
# `isCrossBuild || stdenv.isIntraISACross`, so the variable is never set on a
# native build and the block would be dead weight there. Keeping cc-wrapper.sh
# pristine is what lets native derivations stay byte-identical to upstream and
# therefore substitutable from cache.nixos.org. The matching var_templates_list
# entry is injected in default.nix under the same condition.
if [[ "$isCxx" = 1 ]]; then
    extraBefore+=($NIX_CXXFLAGS_COMPILE_BEFORE_@suffixSalt@)
fi

