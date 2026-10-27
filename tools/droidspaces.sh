# Droidspaces non-GKI helpers (from the official Droidspaces-OSS kernel patches)
# Droidspaces Constants & Functions
# ==========================================
DROIDSPACES_VERSION="${DROIDSPACES_VERSION:-v6.4.5}"
DROIDSPACES_PATCH_BASE="https://raw.githubusercontent.com/ravindu644/Droidspaces-OSS/${DROIDSPACES_VERSION}/Documentation/resources/kernel-patches/non-GKI"
DROIDSPACES_XT_QTAGUID_SHA256="f71898942e0f872c5cf28ebaef0dcd9b9efe7e02f0dfc8310441efa8772fed7d"
DROIDSPACES_CGROUP_SHA256="6d2c9dbe5aa394328c35845e416ac274bade7dce36994b945de75769448219cc"

apply_droidspaces_patch() {
    local description="$1"
    local url="$2"
    local expected_sha256="$3"
    local patch_file="$4"

    echo "Download Droidspaces patch: ${description}"
    curl -fLSs --retry 3 --connect-timeout 20 -o "$patch_file" "$url"
    printf '%s  %s\n' "$expected_sha256" "$patch_file" | sha256sum -c -

    if git apply --check --whitespace=nowarn "$patch_file" 2>/dev/null; then
        git apply --whitespace=nowarn "$patch_file"
        echo "Applied Droidspaces patch: ${description}"
    elif git apply --reverse --check --whitespace=nowarn "$patch_file" 2>/dev/null; then
        echo "Droidspaces patch already applied: ${description}"
    else
        git apply --check --whitespace=nowarn "$patch_file" || true
        echo "ERROR: Droidspaces patch is incompatible with this kernel tree: ${description}"
        echo "Do not continue building a kernel that only passes config checks; this patch prevents a runtime kernel panic."
        exit 1
    fi
}

integrate_droidspaces_non_gki() {
    local kernel_version kernel_patchlevel kernel_series patch_dir

    kernel_version=$(awk '$1 == "VERSION" { print $3; exit }' Makefile)
    kernel_patchlevel=$(awk '$1 == "PATCHLEVEL" { print $3; exit }' Makefile)
    kernel_series="${kernel_version}.${kernel_patchlevel}"

    case "$kernel_series" in
        3.18|4.4|4.9|4.14|4.19)
            ;;
        *)
            echo "ERROR: Detected Linux ${kernel_series}. This script carries Droidspaces non-GKI patches only."
            echo "For a GKI kernel, use the version-specific kABI patches from the official Droidspaces guide."
            exit 1
            ;;
    esac

    if [ ! -f kernel/cgroup/cgroup.c ]; then
        echo "ERROR: This legacy kernel tree lacks kernel/cgroup/cgroup.c."
        exit 1
    fi

    patch_dir=$(mktemp -d /tmp/droidspaces-kernel-patches.XXXXXX)

    if [ -f net/netfilter/xt_qtaguid.c ]; then
        apply_droidspaces_patch \
            "avoid xt_qtaguid kernel panic when container interfaces change" \
            "${DROIDSPACES_PATCH_BASE}/01.fix_kernel_panic_in_xt_qtaguid.patch" \
            "$DROIDSPACES_XT_QTAGUID_SHA256" \
            "${patch_dir}/01-xt_qtaguid-panic.patch"
    else
        echo "xt_qtaguid is not present in this kernel tree; its panic path is absent, so patch 01 is not applicable."
    fi

    apply_droidspaces_patch \
        "restore cgroup file prefixes for Droidspaces/LXC" \
        "${DROIDSPACES_PATCH_BASE}/02.fix_restore%20cgroup%20file%20prefix%20handling%20.patch" \
        "$DROIDSPACES_CGROUP_SHA256" \
        "${patch_dir}/02-cgroup-prefix.patch"

    rm -r -- "$patch_dir"
    echo "Droidspaces ${DROIDSPACES_VERSION} non-GKI runtime patches are ready."
}

configure_droidspaces_non_gki() {
    local out_dir="$1"
    local missing=0 symbol
    local critical_configs=(
        SYSCTL SYSVIPC POSIX_MQUEUE
        NAMESPACES PID_NS UTS_NS IPC_NS
        SECCOMP SECCOMP_FILTER
        CGROUPS CGROUP_DEVICE CGROUP_PIDS MEMCG CGROUP_SCHED
        FAIR_GROUP_SCHED CGROUP_FREEZER
        DEVTMPFS OVERLAY_FS
        NET_NS VETH BRIDGE NETFILTER BRIDGE_NETFILTER
        NF_CONNTRACK IP_NF_IPTABLES IP_NF_FILTER NF_NAT
        IP_NF_TARGET_MASQUERADE
        NETFILTER_XT_TARGET_TCPMSS NETFILTER_XT_MATCH_ADDRTYPE
        NF_CT_NETLINK NF_NAT_REDIRECT
        IP_ADVANCED_ROUTER IP_MULTIPLE_TABLES
    )

    echo "Enable official Droidspaces non-GKI kernel configuration..."
    scripts/config --file "${out_dir}/.config" \
        -e SYSCTL \
        -e SYSVIPC \
        -e POSIX_MQUEUE \
        -e NAMESPACES \
        -e PID_NS \
        -e UTS_NS \
        -e IPC_NS \
        -e SECCOMP \
        -e SECCOMP_FILTER \
        -e CGROUPS \
        -e CGROUP_DEVICE \
        -e CGROUP_PIDS \
        -e MEMCG \
        -e CGROUP_SCHED \
        -e FAIR_GROUP_SCHED \
        -e CGROUP_FREEZER \
        -e CGROUP_NET_PRIO \
        -e DEVTMPFS \
        -e OVERLAY_FS \
        -e TMPFS_POSIX_ACL \
        -e TMPFS_XATTR \
        -e FW_LOADER \
        -e FW_LOADER_USER_HELPER \
        -e FW_LOADER_COMPRESS \
        -e NET_NS \
        -e VETH \
        -e BRIDGE \
        -e NETFILTER \
        -e BRIDGE_NETFILTER \
        -e NETFILTER_ADVANCED \
        -e NF_CONNTRACK \
        -e IP_NF_IPTABLES \
        -e IP_NF_FILTER \
        -e NF_NAT \
        -e IP_NF_TARGET_MASQUERADE \
        -e NETFILTER_XT_TARGET_MASQUERADE \
        -e NETFILTER_XT_TARGET_TCPMSS \
        -e NETFILTER_XT_MATCH_ADDRTYPE \
        -e NF_CT_NETLINK \
        -e NF_CONNTRACK_NETLINK \
        -e NF_NAT_REDIRECT \
        -e IP_ADVANCED_ROUTER \
        -e IP_MULTIPLE_TABLES \
        -e NF_CONNTRACK_IPV4 \
        -e NF_NAT_IPV4 \
        -e IP_NF_NAT \
        -e USER_NS \
        -d ANDROID_PARANOID_NETWORK

    # Resolve dependencies now
    make "${MAKE_OPTS[@]}" olddefconfig 2>/dev/null || true

    if grep -Eq '^CONFIG_PERF_HUMANTASK=(y|m)$' "${out_dir}/.config"; then
        echo "ERROR: CONFIG_PERF_HUMANTASK was re-enabled by Kconfig."
        echo "Droidspaces container startup is unsafe; aborting before compilation."
        exit 1
    fi
    echo "CONFIG_PERF_HUMANTASK is disabled for Droidspaces compatibility."

    for symbol in "${critical_configs[@]}"; do
        if ! grep -qx "CONFIG_${symbol}=y" "${out_dir}/.config"; then
            echo "ERROR: CONFIG_${symbol}=y did not survive olddefconfig."
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo "ERROR: Required Droidspaces configuration is incomplete; aborting before compilation."
        exit 1
    fi

    echo "Droidspaces critical configuration verified after olddefconfig."
}
