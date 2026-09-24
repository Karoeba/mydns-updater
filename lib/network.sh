#!/bin/sh
# IPv4-only MyDNS.JP transport. Uses health budgets, diagnostics and private response storage.
# Sourced by update.sh; not a standalone command.

request() {
    REQUEST_TIMEOUT="$1"
    shift
    health_progress "$REQUEST_TIMEOUT"
    HTTP_CODE=""
    CURL_CODE=0
    : > "$WORK_DIR/response" || fatal "[INTERNAL] RESPONSE_FILE_FAILED"
    HTTP_CODE="$(curl -4 -fsS --connect-timeout 10 --max-time "$REQUEST_TIMEOUT" \
        --output "$WORK_DIR/response" --write-out '%{http_code}' "$@" 2>/dev/null)" || CURL_CODE=$?
}

classify_response() {
    ERROR_MODE=transient
    ERROR_HINT="retry; if persistent check network and service"
    ERROR_CODE=""
    case "$CURL_CODE" in
        0|22) ;;
        1|3|4) ERROR_CODE=URL_OR_PROTOCOL_ERROR; ERROR_MODE=error; ERROR_HINT="check endpoint configuration" ;;
        5|6) ERROR_CODE=DNS_FAILED ;;
        7) ERROR_CODE=CONNECT_FAILED ;;
        28) ERROR_CODE=TIMEOUT ;;
        35) ERROR_CODE=TLS_FAILED; ERROR_HINT="check clock, TLS and endpoint" ;;
        51|58|60|77) ERROR_CODE=CERTIFICATE_ERROR; ERROR_MODE=error; ERROR_HINT="check clock, certificates and endpoint" ;;
        23|26|27) ERROR_CODE=LOCAL_RESOURCE_ERROR; ERROR_MODE=error; ERROR_HINT="check temporary storage and memory" ;;
        52) ERROR_CODE=EMPTY_RESPONSE ;;
        55|56|18) ERROR_CODE=TRANSFER_FAILED ;;
        *) ERROR_CODE=CURL_ERROR ;;
    esac
    if [ -z "$ERROR_CODE" ]; then
        case "$HTTP_CODE" in
            2[0-9][0-9]) [ "$CURL_CODE" -eq 0 ] && return 0; ERROR_CODE=HTTP_ERROR ;;
            401) ERROR_CODE=HTTP_UNAUTHORIZED; ERROR_MODE=error; ERROR_HINT="check credentials and service access" ;;
            403) ERROR_CODE=HTTP_FORBIDDEN; ERROR_MODE=error; ERROR_HINT="check access restrictions; credentials may not be the cause" ;;
            408) ERROR_CODE=HTTP_TIMEOUT ;;
            429) ERROR_CODE=RATE_LIMITED; ERROR_HINT="do not increase request frequency; check service guidance" ;;
            5[0-9][0-9]) ERROR_CODE=HTTP_SERVER_ERROR ;;
            3[0-9][0-9]) ERROR_CODE=HTTP_REDIRECT; ERROR_MODE=error; ERROR_HINT="check endpoint; redirect not followed" ;;
            4[0-9][0-9]) ERROR_CODE=HTTP_CLIENT_ERROR; ERROR_MODE=error; ERROR_HINT="check endpoint and service requirements" ;;
            *) ERROR_CODE=HTTP_STATUS_UNKNOWN ;;
        esac
    fi
    return 1
}

transport_failure() {
    case "$HTTP_CODE" in
        [0-9][0-9][0-9]) SAFE_HTTP="$HTTP_CODE" ;;
        *) SAFE_HTTP=unknown ;;
    esac
    failure "$1" "$2" "$ERROR_CODE" "$3" \
        "curl=$CURL_CODE http=$SAFE_HTTP; $ERROR_HINT; $4"
}

valid_ipv4() {
    printf '%s\n' "$1" | awk '
        {
            if (NR != 1 || split($0, octet, ".") != 4) exit 1
            for (i = 1; i <= 4; i++) {
                if (octet[i] !~ /^[0-9]+$/ || length(octet[i]) > 3 ||
                    octet[i] + 0 > 255 ||
                    (length(octet[i]) > 1 && substr(octet[i], 1, 1) == "0"))
                    exit 1
            }
        }
        END { if (NR == 0) exit 1 }
    '
}

get_current_ipv4() {
    SERVICE=0
    for URL in "$IP_CHECK_URL1" "$IP_CHECK_URL2" "$IP_CHECK_URL3"; do
        SERVICE=$((SERVICE + 1))
        SERVICE_KEY="service.$SERVICE"
        SERVICE_TARGET="IP_CHECK_URL$SERVICE"
        track_target "$SERVICE_KEY" "$URL" "$SERVICE_TARGET"
        request 20 "$URL"
        if classify_response; then
            CANDIDATE="$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "$WORK_DIR/response")"
            if valid_ipv4 "$CANDIDATE"; then
                CURRENT_IPV4="$CANDIDATE"
                recovered "$SERVICE_KEY" "$SERVICE_TARGET"
                recovered ip IP_CHECK
                return 0
            fi
            if [ -z "$CANDIDATE" ]; then ERROR_CODE=EMPTY_RESPONSE; else ERROR_CODE=INVALID_IPV4; fi
            failure "$SERVICE_KEY" "$SERVICE_TARGET" "$ERROR_CODE" fallback "trying next service; check configured service if persistent"
        else
            transport_failure "$SERVICE_KEY" "$SERVICE_TARGET" fallback "trying next service"
        fi
    done
    failure ip IP_CHECK ALL_SERVICES_FAILED transient "All checks failed: skipping this cycle; check network and services if persistent"
    return 1
}

notify_mydns() {
    request 30 -u "$ID:$PASSWORD" https://ipv4.mydns.jp/login.html
    REQUEST_OK=0
    if classify_response; then
        if grep -Fq 'Login and IP address notify OK.' "$WORK_DIR/response"; then
            REQUEST_OK=1
        else
            ERROR_CODE=SUCCESS_NOT_CONFIRMED
            ERROR_MODE=transient
            ERROR_HINT="success response missing; check account and service if persistent"
        fi
    fi
}
