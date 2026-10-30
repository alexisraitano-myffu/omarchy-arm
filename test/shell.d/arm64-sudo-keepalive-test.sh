#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# A stub so the timestamp handling can be observed without authenticating
# anything, and so a machine with passwordless sudo and one without produce
# the same result.
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$STUB_CALLS"
exit "${STUB_SUDO_STATUS:-0}"
SH
chmod +x "$stub_bin/sudo"

export PATH="$stub_bin:$PATH"
export STUB_CALLS="$test_tmp/calls.log"
export OMARCHY_ARM_SUDO_INTERVAL=1

source "$ROOT/install/arm/sudo-keepalive.sh"

calls() {
  grep -c "$1" "$STUB_CALLS" 2>/dev/null || true
}

# A dry run is a description of what would happen. Authenticating is not
# describing, and --dry-run is the flag people reach for precisely because they
# do not yet trust the script with their password.
: >"$STUB_CALLS"
out=$(OMARCHY_ARM_DRY_RUN=1 omarchy_arm_sudo_keepalive_start)
[[ ! -s $STUB_CALLS ]] || fail "a dry run does not authenticate" "$(cat "$STUB_CALLS")"
[[ -z $OMARCHY_ARM_SUDO_KEEPALIVE_PID ]] || fail "a dry run starts no keepalive" "$OMARCHY_ARM_SUDO_KEEPALIVE_PID"
grep -q "sudo -v" <<<"$out" || fail "a dry run says what it would do" "$out"
pass "a dry run neither authenticates nor starts a keepalive"

# The whole point: the timestamp has to still be valid when makepkg shells out
# to sudo, which on aarch64 is a long way past sudo's five-minute default.
: >"$STUB_CALLS"
omarchy_arm_sudo_keepalive_start >/dev/null || fail "the keepalive starts"
[[ -n $OMARCHY_ARM_SUDO_KEEPALIVE_PID ]] || fail "the keepalive records its pid"
(( $(calls '^sudo -v$') == 1 )) || fail "the password is asked for once, up front" "$(cat "$STUB_CALLS")"

sleep 2
refreshes=$(calls '^sudo -n -v$')
(( refreshes >= 2 )) || fail "the timestamp is refreshed while the install runs" "$(cat "$STUB_CALLS")"
pass "the timestamp is primed once and then refreshed in the background"

# And it has to stop. A refresher left running after the script exits keeps
# handing out a valid timestamp to anything else on the machine.
omarchy_arm_sudo_keepalive_stop
[[ -z $OMARCHY_ARM_SUDO_KEEPALIVE_PID ]] || fail "stopping clears the pid" "$OMARCHY_ARM_SUDO_KEEPALIVE_PID"
settled=$(calls '^sudo -n -v$')
sleep 2
(( $(calls '^sudo -n -v$') == settled )) || fail "stopping ends the refreshing" "$(cat "$STUB_CALLS")"
pass "stopping the keepalive ends the refreshing"

omarchy_arm_sudo_keepalive_stop || fail "stopping a keepalive that never started is harmless"
pass "stopping a keepalive that never started is harmless"

# A user who is not in sudoers cannot install anything, and finding that out
# here is worth more than finding it out after the package plan is printed.
: >"$STUB_CALLS"
status=0
STUB_SUDO_STATUS=1 omarchy_arm_sudo_keepalive_start >/dev/null || status=$?
(( status != 0 )) || fail "a failed authentication is reported to the caller"
[[ -z $OMARCHY_ARM_SUDO_KEEPALIVE_PID ]] || fail "a failed authentication leaves nothing running" "$OMARCHY_ARM_SUDO_KEEPALIVE_PID"
pass "a failed authentication fails the start and leaves nothing running"

# Priming after the first sudo would defeat the purpose: the prompt has to come
# before the keyring repair, which is the first thing that escalates.
keepalive_line=$(grep -n 'omarchy_arm_sudo_keepalive_start' "$ROOT/install.sh" | head -1 | cut -d: -f1)
keyring_line=$(grep -n 'omarchy_arm_keyring_repair' "$ROOT/install.sh" | head -1 | cut -d: -f1)
[[ -n $keepalive_line && -n $keyring_line ]] ||
  fail "install.sh starts the sudo keepalive"
(( keepalive_line < keyring_line )) ||
  fail "the keepalive is started before the first command that needs sudo"
grep -q 'omarchy_arm_sudo_keepalive_stop' "$ROOT/install.sh" ||
  fail "install.sh stops the keepalive on the way out"
pass "install.sh primes the timestamp before its first sudo and stops it afterwards"
