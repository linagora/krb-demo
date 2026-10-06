#!/bin/bash
# End-to-end checks of a deployed lab (lab/lab.sh up, then lab/lab.sh deploy).
#
# Usage: lab/check.sh
#
# Runs, through SSH to the VMs, what a user and an administrator would do:
# SSO sign-ins, console rights, Kerberos on pc1, a login on pc1, and the life
# of a computer (create, one-time password, join, delete). It assumes the demo
# passwords (password = login) and leaves the directory as it found it.
# Prints one line per check, and exits with the number of failures.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LAB=$HERE/lab.sh
export LAB_DIR=${LAB_DIR:-$HOME/.cache/krb-demo-lab}
BASE=dc=star,dc=wars
FAILED=0

ok() { printf '  \e[32mok\e[0m    %s\n' "$1"; }
ko() { printf '  \e[31mFAIL\e[0m  %s\n' "$1"; FAILED=$((FAILED + 1)); }
check() { # check "description" command...
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then ok "$what"; else ko "$what"; fi
}
on() { "$LAB" ssh "$@"; }

# On dc: sign in on the console through the SSO portal, cookies in /tmp/jar-<user>.
SSO_LOGIN='
sso() {
  local u=$1 p=$2 jar=/tmp/jar-$1 loc form token url
  rm -f "$jar"
  loc=$(curl -s -b "$jar" -c "$jar" -o /dev/null -w "%{redirect_url}" https://directory.star.wars/login)
  form=$(curl -s -b "$jar" -c "$jar" -L "$loc")
  token=$(sed -n "s/.*name=\"token\" value=\"\([^\"]*\)\".*/\1/p" <<<"$form" | head -1)
  url=$(sed -n "s/.*name=\"url\" value=\"\([^\"]*\)\".*/\1/p" <<<"$form" | head -1)
  curl -s -b "$jar" -c "$jar" -L -o /dev/null -w "%{url_effective}" \
    --data-urlencode "user=$u" --data-urlencode "password=$p" \
    --data-urlencode "token=$token" --data-urlencode "url=$url" https://auth.star.wars/
}
'

echo "Services"
check "dc: the SSO and the console run" on dc 'test "$(sudo docker ps -q | wc -l)" -ge 2'
check "dc: the join service runs" on dc 'systemctl is-active sw-join'
check "dc: the computers and Unix ids timers run" on dc 'systemctl is-active sw-computers.timer sw-posix-accounts.timer'
check "pc1: sssd is online" on pc1 'sudo sssctl domain-status star.wars | grep -q "Online status: Online"'

echo "SSO and console"
check "yoda signs in to the console through the SSO" on dc "$SSO_LOGIN"'
  [ "$(sso yoda yoda)" = https://directory.star.wars/static/console/ ]'
check "yoda administers the whole directory" on dc "$SSO_LOGIN"'
  sso yoda yoda >/dev/null
  curl -s -b /tmp/jar-yoda https://directory.star.wars/api/v1/authz/scope | jq -e "[.branches[].path] == [\"organization\"]"'
check "dvador administers the Galactic Empire only" on dc "$SSO_LOGIN"'
  sso dvador dvador >/dev/null
  curl -s -b /tmp/jar-dvador https://directory.star.wars/api/v1/authz/scope | jq -e "[.branches[].path] == [\"Galactic Empire\"]"'
check "a wrong password is refused" on dc "$SSO_LOGIN"'
  [ "$(sso hsolo wrong)" != https://directory.star.wars/static/console/ ]'

echo "Workstation"
check "pc1 knows the directory's accounts" on pc1 'getent passwd hsolo | grep -q ":/home/hsolo:"'
check "pc1's key is valid" on pc1 'sudo kinit -k -c MEMORY:x host/pc1.star.wars'
check "kinit hsolo works from pc1" on pc1 'echo hsolo | KRB5CCNAME=MEMORY:x kinit hsolo'
askpass=$(mktemp)
trap 'rm -f "$askpass"' EXIT
printf '#!/bin/sh\necho hsolo\n' >"$askpass"
chmod +x "$askpass"
check "hsolo logs in on pc1 and gets a ticket" env SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force \
  setsid ssh -p 2223 -o IdentitiesOnly=yes -o IdentityAgent=none -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  hsolo@127.0.0.1 'klist | grep -q "Default principal: hsolo@STAR.WARS"'

echo "Computers"
API=https://directory.star.wars/api/v1/ldap/computers
PREP="$SSO_LOGIN"'
  sso yoda yoda >/dev/null
  api() { curl -s -b /tmp/jar-yoda -H "Content-Type: application/json" "$@"; }
'
check "yoda creates the computer check-pc" on dc "$PREP"'
  api -X POST -o /dev/null -w "%{http_code}" '"$API"' \
    -d "{\"cn\":\"check-pc\",\"twakeDepartmentLink\":\"ou=organization,'"$BASE"'\"}" | grep -q 201'
check "its principal appears, marked" on dc '
  for _ in $(seq 1 30); do
    sudo kadmin.local -q "getprinc host/check-pc.star.wars" | grep -q "Policy: workstation" && exit 0
    sleep 2
  done; exit 1'
OTP=$(on dc "$PREP"'
  until sudo ldapsearch -LLL -Q -Y EXTERNAL -H ldapi:/// -b cn=check-pc,ou=computers,'"$BASE"' pwdPolicySubentry | grep -q pwd; do sleep 2; done
  api -X POST -d "{}" '"$API"'/check-pc/password | jq -r .password' 2>/dev/null)
JOIN='j() { printf "%s" "$2" | curl -s -o /tmp/kt -w "%{http_code}" --data-urlencode host=$1 --data-urlencode "password@-" https://dc.star.wars/join; }'
check "its one-time password gets its keytab" on pc1 "$JOIN"'
  [ "$(j check-pc '"'$OTP'"')" = 200 ] && klist -k /tmp/kt | grep -q host/check-pc.star.wars'
check "the same password is refused afterwards" on pc1 "$JOIN"'
  [ "$(j check-pc '"'$OTP'"')" = 403 ]'
check "a computer named dc is refused" on dc "$PREP"'
  api -X POST -o /dev/null -w "%{http_code}" '"$API"' \
    -d "{\"cn\":\"dc\",\"twakeDepartmentLink\":\"ou=organization,'"$BASE"'\"}" | grep -q 400'
check "deleting it deletes its principal" on dc "$PREP"'
  api -X DELETE -o /dev/null '"$API"'/check-pc
  sudo systemctl start sw-computers.service
  ! sudo kadmin.local -q "listprincs host/*" | grep -q host/check-pc'

echo
if [ "$FAILED" = 0 ]; then echo "All checks passed."; else echo "$FAILED check(s) failed."; fi
exit "$FAILED"
