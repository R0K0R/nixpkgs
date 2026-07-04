# pkg-config Wrapper hygiene
#
# See comments in cc-wrapper's setup hook. This works exactly the same way.

# Skip setup hook if we're neither a build-time dep, nor, temporarily, doing a
# native compile.
#
# TODO(@Ericson2314): No native exception
# In pseudo-cross (same ISA, different gcc.arch), HOST package setup hooks run
# via F4's _addToEnv relax, but $hostOffset is unset in that call context so
# (( "$hostOffset" < 0 )) evaluates false.  Allow HOST packages' pkgconfig dirs
# to reach PKG_CONFIG_PATH so the HOST pkg-config wrapper's add-flags.sh can
# copy them into PKG_CONFIG_PATH_<salt> at wrapper invocation time.
[[ -z ${strictDeps-} ]] || (( "$hostOffset" < 0 )) || [[ "${NIX_IS_INTRA_ISA_CROSS-}" == "1" ]] || return 0

pkgConfigWrapper_addPkgConfigPath () {
    # See ../setup-hooks/role.bash
    local role_post
    getHostRoleEnvHook

    addToSearchPath "PKG_CONFIG_PATH${role_post}" "$1/lib/pkgconfig"
    addToSearchPath "PKG_CONFIG_PATH${role_post}" "$1/share/pkgconfig"
}

# See ../setup-hooks/role.bash
getTargetRole
getTargetRoleWrapper

addEnvHooks "$targetOffset" pkgConfigWrapper_addPkgConfigPath

export PKG_CONFIG${role_post}=@targetPrefix@@baseBinName@

# No local scope in sourced file
unset -v role_post
