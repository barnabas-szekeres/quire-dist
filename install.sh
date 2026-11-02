#!/usr/bin/env bash
# Installs Quire on a reMarkable Paper Pure, or brings the Quire on it up to date. Run it on a
# computer (macOS or Linux; on Windows, in WSL) with the tablet connected over USB:
#
#   curl -fsSL https://barnabas-szekeres.github.io/quire-dist/install.sh | bash
#
# It installs the latest release from this repository's App Store index. On a tablet that has
# Quire already, it updates Quire if there is a newer release, puts back the boot stub that a
# reMarkable OS update removes, and starts Quire if it isn't running. Run it again after every
# reMarkable OS update.
#
#   --host <address>  the tablet's address, without asking (default 10.11.99.1, over USB)
#   --yes             don't wait for Enter after the instructions
#
# Options go after `bash -s --`: curl -fsSL …/install.sh | bash -s -- --host 192.168.1.20
#
# For trying it out (not for users): QUIRE_INSTALL_ROOT installs into another directory on the
# tablet and leaves the running Quire and the boot stub alone; QUIRE_INSTALL_TOOL is a local
# quire built for the tablet, used in place of the release's quire-rmppure.

# Commands for the tablet are put together here, on purpose.
# shellcheck disable=SC2029
set -euo pipefail

INDEX="https://barnabas-szekeres.github.io/quire-dist/v1/index.json"
DOWNLOADS="https://github.com/barnabas-szekeres/quire-dist/releases/download"
DEFAULT_HOST="10.11.99.1"
ROOT="${QUIRE_INSTALL_ROOT:-/home/root/.local/share/quire}"
TOOL="${QUIRE_INSTALL_TOOL:-}"
# Where the downloads wait on the tablet; removed at the end.
INCOMING="/home/root/quire-install"
SYSTEM_ID="dev.quire.system"
MIN_OS="3.28.0"
# Room for the download, its unpacked copy and the store's staging (KB).
MIN_FREE_KB=400000

host=""
wait_for_enter=1
while [ $# -gt 0 ]; do
    case "$1" in
        --host) host="${2:?--host needs an address}"; shift 2 ;;
        --host=*) host="${1#--host=}"; shift ;;
        --yes | -y) wait_for_enter=0; shift ;;
        -h | --help)
            cat <<'EOF'
Installs Quire on a reMarkable Paper Pure over USB, or brings the Quire on it up to date.

  --host <address>  the tablet's address, without asking (default 10.11.99.1)
  --yes             don't wait for Enter after the instructions
EOF
            exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done

if [ -t 1 ]; then bold=$'\033[1m'; plain=$'\033[0m'; else bold=""; plain=""; fi
say() { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$bold" "$plain" "$*"; }
fail() { printf '\n%sCould not finish:%s %s\n' "$bold" "$plain" "$*" >&2; exit 1; }

# Questions come from the terminal, also when the script itself comes through a pipe from curl.
ask() {
    local answer=""
    if ! { true < /dev/tty; } 2>/dev/null; then
        fail "no terminal to ask in. Run it in a terminal, or pass --host <address> --yes."
    fi
    printf '%s' "$1" > /dev/tty
    IFS= read -r answer < /dev/tty || true
    printf '%s' "$answer"
}

# a < b, for versions like 3.28.0.172 or 0.5.9 (what follows a "-" is ignored).
version_lt() {
    local IFS=. i
    local -a a b
    read -r -a a <<< "${1%%-*}"
    read -r -a b <<< "${2%%-*}"
    for i in 0 1 2 3; do
        if [ "${a[i]:-0}" -lt "${b[i]:-0}" ]; then return 0; fi
        if [ "${a[i]:-0}" -gt "${b[i]:-0}" ]; then return 1; fi
    done
    return 1
}

sha256_check() {
    if command -v sha256sum > /dev/null; then sha256sum -c --quiet "$@"; else shasum -a 256 -c --quiet "$@"; fi
}

for tool in curl ssh scp; do
    command -v "$tool" > /dev/null || fail "$tool is missing on this computer."
done
command -v sha256sum > /dev/null || command -v shasum > /dev/null || fail "sha256sum (or shasum) is missing on this computer."

cat <<EOF

${bold}Quire installer${plain}

Before you start:
 1. Sync your notebooks: turning on Developer Mode resets the tablet to
    factory settings.
 2. On the tablet: Settings → General → Software → Advanced → Developer mode.
    Then set the tablet up again.
 3. Connect it to this computer with a USB cable, and unlock it.
 4. Its SSH password: Settings → General → About → Copyrights and licenses,
    under "GPLv3 Compliance".

EOF
if [ "$wait_for_enter" = 1 ]; then
    ask "Already done (or updating Quire)? Press Enter. " > /dev/null
    say ""
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/quire-install.XXXXXX")"
control="$work/ssh"
ssh_opts=(-o ControlPath="$control" -o ConnectTimeout=8 -o ServerAliveInterval=10 -o StrictHostKeyChecking=accept-new)
connected=0
cleanup() {
    if [ "$connected" = 1 ]; then
        ssh "${ssh_opts[@]}" "root@$host" "rm -rf $INCOMING" > /dev/null 2>&1 || true
        ssh "${ssh_opts[@]}" -O exit "root@$host" > /dev/null 2>&1 || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

# The tablet: an address that answers SSH (a password not yet given still means it answers).
while :; do
    if [ -z "$host" ]; then
        host="$(ask "Tablet address [$DEFAULT_HOST]: ")"
        host="${host:-$DEFAULT_HOST}"
    fi
    host="${host#root@}"
    probe="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        -o PreferredAuthentications=none "root@$host" true 2>&1)" && break
    case "$probe" in
        *"Permission denied"* | *"No more authentication methods"*) break ;;
        *"IDENTIFICATION HAS CHANGED"*)
            fail "the tablet at $host has new SSH keys (as after Developer Mode reset it). If this is your tablet, forget the old ones with: ssh-keygen -R $host" ;;
    esac
    say "No answer from $host. Is the tablet connected with USB, awake and unlocked, and in Developer Mode?"
    if [ "$wait_for_enter" = 0 ]; then fail "no answer from $host."; fi
    host=""
done

step "Connecting to root@$host (asks for the tablet's SSH password once)"
ssh "${ssh_opts[@]}" -o ControlMaster=yes -o ControlPersist=600 -fN "root@$host" \
    || fail "couldn't log in to root@$host. The password is in Settings → General → About → Copyrights and licenses."
connected=1
tablet() { ssh "${ssh_opts[@]}" "root@$host" "$@"; }

# What the tablet is and has, as key=value lines.
facts="$(tablet "ROOT='$ROOT' SYSTEM_ID='$SYSTEM_ID' sh -s" <<'EOF'
echo "machine=$(cat /sys/devices/soc0/machine 2>/dev/null)"
echo "os=$(sed -n 's/^IMG_VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release)"
systemctl is-active -q home.mount && echo "unlocked=1"
echo "free_kb=$(df -k /home 2>/dev/null | tail -n 1 | awk '{print $(NF-2)}')"
quire="$ROOT/pkgs/$SYSTEM_ID/current/bin/quire"
if [ -x "$quire" ]; then
    "$quire" list --root "$ROOT" 2>/dev/null | awk -v id="$SYSTEM_ID" '$1 == id { print "installed=" $2; print "origin=" $NF }'
fi
[ -e /etc/systemd/system/quire.service ] && echo "stub=1"
systemctl is-active -q quire.service && echo "running=1"
[ -e "$ROOT/boot/disable" ] && echo "disabled=1"
true
EOF
)" || fail "couldn't read what the tablet has."
fact() { printf '%s\n' "$facts" | sed -n "s/^$1=//p" | tail -n 1; }
machine="$(fact machine)"
os="$(fact os)"
installed="$(fact installed)"
origin="$(fact origin)"
free_kb="$(fact free_kb)"

case "$(printf '%s' "$machine" | tr '[:upper:]' '[:lower:]')" in
    *tatsu*) ;;
    *) fail "Quire runs on the reMarkable Paper Pure only; this tablet is \"${machine:-unknown}\"." ;;
esac
[ -n "$os" ] || fail "couldn't tell the tablet's software version."
if version_lt "$os" "$MIN_OS"; then
    fail "Quire needs reMarkable software $MIN_OS or newer; this tablet has $os. Update it in Settings → General → Software."
fi
[ "$(fact unlocked)" = 1 ] || fail "the tablet is locked. Unlock it (enter its passcode), then run this again."
step "reMarkable Paper Pure, software $os${installed:+, Quire $installed}"

# The latest release, from the index (its system entry comes first).
step "Looking up the latest Quire"
index="$(curl -fsSL "$INDEX")" || fail "couldn't read the App Store index ($INDEX)."
tag="$(printf '%s\n' "$index" | grep -o '"tag": *"quire-v[^"]*"' | sed -n '1s/.*"\(quire-v[^"]*\)"/\1/p' || true)"
[ -n "$tag" ] || fail "the App Store index has no Quire release."
latest="${tag#quire-v}"

# Install when there is none, a developer build, or an older one.
install=0
if [ -z "$installed" ]; then
    install=1
    step "Installing Quire $latest"
elif [ "$origin" = "(Dev)" ]; then
    install=1
    step "Replacing the developer build $installed with Quire $latest"
elif version_lt "$installed" "$latest"; then
    install=1
    step "Updating Quire $installed → $latest"
elif [ "$installed" = "$latest" ]; then
    step "Quire $installed is the latest"
else
    step "Quire $installed is newer than the latest release ($latest); keeping it"
fi

quire="$ROOT/pkgs/$SYSTEM_ID/current/bin/quire"
if [ "$install" = 1 ]; then
    if [ -n "$free_kb" ] && [ "$free_kb" -lt "$MIN_FREE_KB" ]; then
        fail "the tablet has only $((free_kb / 1024)) MB free; Quire needs about $((MIN_FREE_KB / 1024)) MB."
    fi
    files=(app.tar.zst app.tar.zst.minisig manifest.json)
    for file in "${files[@]}"; do
        curl -fsSL -o "$work/$file" "$DOWNLOADS/$tag/$file" || fail "couldn't download $file of $tag."
    done
    # A tablet without Quire has nothing to unpack and check the bundle with: the release's quire
    # does it, which checks the bundle's signature against Quire's own key.
    if [ -z "$installed" ]; then
        if [ -n "$TOOL" ]; then
            cp "$TOOL" "$work/quire-rmppure"
        else
            for file in quire-rmppure SHA256SUMS; do
                curl -fsSL -o "$work/$file" "$DOWNLOADS/$tag/$file" || fail "couldn't download $file of $tag."
            done
            (cd "$work" && sha256_check SHA256SUMS) || fail "the download of quire-rmppure is damaged; try again."
        fi
        files+=(quire-rmppure)
    fi
    say "    Copying to the tablet…"
    tablet "rm -rf $INCOMING && mkdir -p $INCOMING"
    (cd "$work" && scp -q "${ssh_opts[@]}" "${files[@]}" "root@$host:$INCOMING/") \
        || fail "couldn't copy Quire to the tablet."
    installer="$quire"
    if [ -z "$installed" ]; then
        tablet "chmod 755 $INCOMING/quire-rmppure"
        installer="$INCOMING/quire-rmppure"
    fi
    tablet "$installer install --root '$ROOT' --grant-all $INCOMING/app.tar.zst" | sed 's/^/    /' \
        || fail "Quire's installation didn't go through (see above)."
fi

if [ -n "${QUIRE_INSTALL_ROOT:-}" ]; then
    # A trial into another directory: what the boot stub would do, nothing more.
    tablet "$quire bootstrap --root '$ROOT' --dry-run" | sed 's/^/    /'
    step "Installed into $ROOT (a trial: the running Quire and the boot stub are as they were)"
    exit 0
fi

# Quire starting with the tablet: the boot stub, which a reMarkable OS update removes.
if [ "$(fact stub)" != 1 ] || [ -z "$installed" ]; then
    step "Making Quire start with the tablet"
    tablet "$quire bootstrap" | sed 's/^/    /' || fail "couldn't put Quire's boot stub in place (see above)."
fi

# Running the new version, or running at all.
if [ "$(fact running)" = 1 ]; then
    if [ "$install" = 1 ]; then
        step "Restarting Quire"
        tablet "systemctl restart quire.service" || fail "Quire didn't restart (see: ssh root@$host journalctl -u quire.service)."
    fi
else
    step "Starting Quire"
    # Turned off by `quire disable`, or by quire-boot after runs that went wrong: on again.
    tablet "$quire enable" > /dev/null
    tablet "systemctl start quire.service" || fail "Quire didn't start (see: ssh root@$host journalctl -u quire.service)."
fi

version="$latest"
if [ "$install" = 0 ]; then version="$installed"; fi
cat <<EOF

${bold}Quire $version is on the tablet.${plain}

 - Your notebooks are in Notebooks, on Quire's home screen.
 - More apps: Settings → Apps. Quire and its apps update themselves from there.
 - After a reMarkable software update, run this again: the update takes Quire
   off, and this puts it back.
 - Back to the reMarkable software until the next restart:
     ssh root@$host $quire rescue
   For good: "$quire disable" (and "enable" to undo).
EOF
