#!/bin/sh

CONFIG="/app/mydns.conf"
DEFAULT_INTERVAL=3600

update_account() {
    if [ -z "$SECTION" ]; then
        return
    fi

    NOW="$(TZ=Asia/Tokyo date "+%Y-%m-%d %H:%M:%S JST")"

    if [ -z "$ID" ] || [ -z "$PASSWORD" ] || [ -z "$DOMAIN" ]; then
        echo "$NOW [$SECTION] MyDNS update: CONFIG ERROR"
        return
    fi

    RESPONSE="$(curl -fsS \
        -u "$ID:$PASSWORD" \
        https://ipv4.mydns.jp/login.html \
        2>/dev/null)"

    if echo "$RESPONSE" | grep -q "Login and IP address notify OK."; then
        echo "$NOW [$DOMAIN] MyDNS update: OK"
    else
        echo "$NOW [$DOMAIN] MyDNS update: FAILED"
    fi
}

while true; do

    INTERVAL="$DEFAULT_INTERVAL"

    SECTION=""
    ID=""
    PASSWORD=""
    DOMAIN=""

    while IFS= read -r LINE || [ -n "$LINE" ]; do

        # Windows‚ÌCRLF‚É‚à‘Î‰ž
        LINE="$(printf '%s' "$LINE" | sed 's/\r$//')"

        case "$LINE" in
            "")
                ;;

            \#*|\;*)
                ;;

            INTERVAL=*)
                INTERVAL="${LINE#INTERVAL=}"
                ;;

            \[*\])
                update_account

                SECTION="${LINE#\[}"
                SECTION="${SECTION%\]}"

                ID=""
                PASSWORD=""
                DOMAIN=""
                ;;

            ID=*)
                ID="${LINE#ID=}"
                ;;

            PASSWORD=*)
                PASSWORD="${LINE#PASSWORD=}"
                ;;

            DOMAIN=*)
                DOMAIN="${LINE#DOMAIN=}"
                ;;
        esac

    done < "$CONFIG"

    update_account

    case "$INTERVAL" in
        ''|*[!0-9]*|0)
            NOW="$(TZ=Asia/Tokyo date "+%Y-%m-%d %H:%M:%S JST")"
            echo "$NOW [CONFIG] Invalid INTERVAL: using ${DEFAULT_INTERVAL}s"
            INTERVAL="$DEFAULT_INTERVAL"
            ;;
    esac

    sleep "$INTERVAL"
done