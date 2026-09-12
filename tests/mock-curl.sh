#!/bin/sh
auth=''
url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -u) auth="$2"; shift ;;
        https://*) url="$1" ;;
    esac
    shift
done
if [ "$url" = https://ipv4.mydns.jp/login.html ]; then
    account="${auth%%:*}"
    echo "$account" >> /tmp/mock/updates
    # Account 1 must already be on disk when account 2 is contacted.
    if [ "$account" = two ] && [ -f /tmp/mock/check-immediate ]; then
        expected="$(cat /tmp/mock/ip)"
        actual="$(awk '/^\[/{selected=($0=="[1]")} selected && /^LAST_IPV4=/{sub(/^LAST_IPV4=/, ""); print; exit}' /state/state.conf)"
        [ "$actual" = "$expected" ] || {
            touch /tmp/mock/immediate-failed
            exit 1
        }
    fi
    [ ! -f "/tmp/mock/fail-$account" ] || exit 22
    if [ -f "/tmp/mock/reject-$account" ]; then
        echo 'Login failed'
    else
        echo 'Login and IP address notify OK.'
    fi
    exit 0
fi
case "$url" in
    https://api.ipify.org) service=1 ;;
    https://checkip.amazonaws.com/) service=2 ;;
    https://ipv4.ifconfig.me/ip) service=3 ;;
    https://test.invalid/one) service=1 ;;
    https://test.invalid/two) service=2 ;;
    https://test.invalid/three) service=3 ;;
    *) exit 2 ;;
esac
echo "$service" >> /tmp/mock/checks
[ ! -f "/tmp/mock/fail-service-$service" ] || exit 28
if [ -f "/tmp/mock/invalid-service-$service" ]; then
    echo '999.2.3.4'
else
    cat /tmp/mock/ip
fi
