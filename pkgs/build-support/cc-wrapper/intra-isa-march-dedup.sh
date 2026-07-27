# Deduplicate -march/-mcpu/-mtune: build systems that do per-object ISA
# dispatch (e.g., embree compiling SSE2/SSE4.2/AVX2 variants) pass explicit
# -march= flags per object. Without this fix, an ambient nix-injected
# -march= (appended last via extraAfter, e.g. from a gcc.arch tuned stdenv)
# silently overrides the per-object -march, collapsing ISA namespaces and
# causing link-time symbol collisions. When the user supplies
# -march/-mcpu/-mtune in params, strip the corresponding nix-injected flag
# from NIX_CFLAGS_COMPILE so the user's value wins. This is a no-op on
# untuned stdenvs, which have no ambient -march to begin with.
#
# Spliced into cc-wrapper.sh only for gcc.arch-tuned stdenvs -- see the
# `wrapper` attr in default.nix. Keeping cc-wrapper.sh itself pristine is what
# lets untuned/native derivations stay byte-identical to upstream and therefore
# substitutable from cache.nixos.org.
_march_march=0 _march_mcpu=0 _march_mtune=0
for _march_p in ${params+"${params[@]}"}; do
    case "$_march_p" in
        -march=*) _march_march=1 ;;
        -mcpu=*)  _march_mcpu=1 ;;
        -mtune=*) _march_mtune=1 ;;
    esac
done
if [[ $_march_march == 1 || $_march_mcpu == 1 || $_march_mtune == 1 ]]; then
    _march_filtered=()
    for _march_f in $NIX_CFLAGS_COMPILE_@suffixSalt@; do
        case "$_march_f" in
            -march=*) [[ $_march_march == 0 ]] && _march_filtered+=("$_march_f") ;;
            -mcpu=*)  [[ $_march_mcpu  == 0 ]] && _march_filtered+=("$_march_f") ;;
            -mtune=*) [[ $_march_mtune == 0 ]] && _march_filtered+=("$_march_f") ;;
            *) _march_filtered+=("$_march_f") ;;
        esac
    done
    NIX_CFLAGS_COMPILE_@suffixSalt@="${_march_filtered[*]}"
fi

