#!/bin/sh
# keepalived-gateway.sh. Keep the default gateway and route available.
#
# Copyright (c) 2025 Semyon A Mironov
#
# Authors: Semyon A Mironov <atwis@atwis.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

CONFIG_FILE="${1:-/etc/keepalived-gateway.conf}"

interval2sec ()
{
    case "${1%[smhdwMy]}" in
        *[!0123456789]*)
            echo "invalid value in the '$2' variable: '$1'"
            echo "acceptable values for the '$2' variable are an integer indicating the number of [s]econds, [m]inutes, [h]ours, [d]ays, [w]eeks, [M]onths or [y]ears"
            return 1
    esac
    case "$1" in
        *m) INTERVAL="${1%m}"
            INTERVAL="$((INTERVAL * 60))" ;;
        *h) INTERVAL="${1%h}"
            INTERVAL="$((INTERVAL * 3600))" ;;
        *d) INTERVAL="${1%d}"
            INTERVAL="$((INTERVAL * 86400))" ;;
        *w) INTERVAL="${1%w}"
            INTERVAL="$((INTERVAL * 604800))" ;;
        *M) INTERVAL="${1%M}"
            INTERVAL="$((INTERVAL * 2678400))" ;;
        *y) INTERVAL="${1%y}"
            INTERVAL="$((INTERVAL * 32140800))" ;;
        *)  INTERVAL="${1%s}" ;;
    esac
    echo "$INTERVAL"
}

include_config ()
{
    test -f "$CONFIG_FILE" || {
        echo "no such config file: '$CONFIG_FILE'"
        return 1
    }

    test -r "$CONFIG_FILE" || {
        echo "no read permission: '$CONFIG_FILE'"
        return 1
    }

    . "$CONFIG_FILE" || return

    test "${GATEWAY:-}" || {
        echo "variable is empty: 'GATEWAY'"
        return 1
    }

    test "${INTERFACE:-}" || {
        echo "variable is empty: 'INTERFACE'"
        return 1
    }

    PING_INTERVAL="$(interval2sec "${PING_INTERVAL:-10}" PING_INTERVAL)" || {
        echo "$PING_INTERVAL"
        return 1
    }

    SPEEDTEST_INTERVAL="$(interval2sec "${SPEEDTEST_INTERVAL:-3600}" SPEEDTEST_INTERVAL)" || {
        echo "$SPEEDTEST_INTERVAL"
        return 1
    }
}

check_ping ()
{
    ping -W 3 -c 3 "$1" >/dev/null 2>&1
}

get_gataway ()
{
    set -- $GATEWAY
    CURRENT_GATEWAY="$1"
    shift
    set -- "$@" "$CURRENT_GATEWAY"
    GATEWAY="$@"
    GATEWAY_NUM="$#"
}

get_default_route ()
{
    ROUTE="$(ip r | grep "\<$INTERFACE\>" | grep '\<default\>')" &&
    echo "${ROUTE%"${ROUTE##*[![:blank:]]}"}"
}

ip_route ()
{
    ROUTE="$2"
    EXEC="ip route $1 $ROUTE"
    $EXEC && echo "$EXEC"
}

add_default_route ()
{
    get_gataway
    NEW_ROUTE="default via $CURRENT_GATEWAY dev $INTERFACE"
    CURRENT_ROUTE="$(get_default_route)" && {
        test "$CURRENT_ROUTE" = "$NEW_ROUTE" || {
            ip_route del "$CURRENT_ROUTE"
            false
        }
    } || {
        CURRENT_ROUTE="$NEW_ROUTE"
        ip_route add "$NEW_ROUTE"
    }
}

get_time ()
{
    date "+%s"
}

speedtest_interval_passed ()
{
    test "${END_TEST:-}" || return 0
    test "$(($(get_time) - END_TEST))" -ge "$SPEEDTEST_INTERVAL"
}

bit2human ()
{
    BIT="${1:-0}" REMAINS='' SIZE=1
    while test "$BIT" -gt 1000
    do
        REMAINS="$(printf ".%02d" $((BIT % 1000 * 100 / 1000)))"
        BIT=$((BIT / 1000))
        SIZE=$((SIZE + 1))
    done
    set -- bit Kbit Mbit Gbit Tbit Ebit Pbit Zbit Ybit
    eval SIZE=\$$SIZE
    echo "$BIT${REMAINS:-} $SIZE"
}

speedtest ()
{
    DLFILE=$(mktemp /tmp/download.XXXXXX 2>&1) || {
        RETURN=$?
        echo "failed to create a temporary file: '$DLFILE'"
        return "$RETURN"
    }
    START_TEST="$(get_time)"
    OUTPUT="$(timeout 15 wget "http://$REMOTE_HOST/$SPEEDTEST_PATH" -O "$DLFILE" -o -)" || {
        RETURN=$?
        test "$RETURN" -eq 124 || {
            echo "$OUTPUT"
            return "$RETURN"
        }
        RETURN=0
    }
    END_TEST="$(get_time)"
    BYTE="$(awk '{s+=$1} END {print s}' "$DLFILE" 2>&1)" || {
        RETURN=$?
        echo "$BYTE"
        return "$RETURN"
    }
    BIT="$((BYTE * 16))"
    BIT="$((BIT / $((END_TEST - START_TEST))))"
    SPEED="$(bit2human "$BIT")/s"
    rm -f "$DLFILE"
}

select_gateway ()
{
    speedtest_interval_passed || return 0
    NEW_ROUTE= BEST_BIT= COUNT=1
    while test "$COUNT" -le "$GATEWAY_NUM"
    do
        COUNT="$((COUNT + 1))"
        TMP_ROUTE="$REMOTE_HOST via $CURRENT_GATEWAY dev $INTERFACE"
        echo "running speedtest every '$SPEEDTEST_INTERVAL seconds' for a temp route: '$TMP_ROUTE'"
        ip_route add "$TMP_ROUTE" >/dev/null || return 0

        if check_ping "$REMOTE_HOST"
        then
            speedtest || cleanup || continue
            echo "route speed: $SPEED"
            test "${BEST_BIT:-0}" -ge "$BIT" || {
                BEST_BIT="$BIT"
                NEW_ROUTE="default via $CURRENT_GATEWAY dev $INTERFACE"
            }
        elif check_ping "$CURRENT_GATEWAY"
        then
            echo "host is unavailable: '$REMOTE_HOST'"
        else
            echo "gateway is unavailable: '$CURRENT_GATEWAY'"
        fi

        ip_route del "$TMP_ROUTE" >/dev/null 2>&1
        get_gataway
    done
    test -z "${NEW_ROUTE:-}" || {
        test "$(get_default_route)" = "$NEW_ROUTE" || {
            ip_route del "$ROUTE"
            ip_route add "$NEW_ROUTE"
            CURRENT_ROUTE="$NEW_ROUTE"
        }
    }
}

del_tmp_rout ()
{
    if  test "${REMOTE_HOST:-}" &&
        TMP_ROUTE="$(ip r | grep "^$REMOTE_HOST via")"
    then
        ip_route del "$TMP_ROUTE"
    fi
}

cleanup ()
{
    RETURN=$?
    rm -f "$DLFILE" || RETURN=$?
    del_tmp_rout    || RETURN=$?
    return "$RETURN"
}

cleanup_and_exit ()
{
    cleanup || RETURN=$?
    exit "$RETURN"
}

trap "cleanup_and_exit" HUP INT TERM
include_config && del_tmp_rout && add_default_route || exit

while :
do
    echo "the current route: '$CURRENT_ROUTE'"
    if test "${REMOTE_HOST:-}"
    then
        if check_ping "$REMOTE_HOST"
        then
            echo "host is available: '$REMOTE_HOST'"
            test "$GATEWAY_NUM" -eq 1 ||
            test -z "${SPEEDTEST_PATH:-}" ||
            select_gateway
        else
            if check_ping  "$CURRENT_GATEWAY"
            then
                echo "host is unavailable: '$REMOTE_HOST'"
                false
            else
                echo "gateway is unavailable: '$CURRENT_GATEWAY'"
                false
            fi
        fi
    elif check_ping "$CURRENT_GATEWAY"
    then
        echo "gateway is available: '$CURRENT_GATEWAY'"
    else
        echo "gateway is unavailable: '$CURRENT_GATEWAY'"
        false
    fi || test "$GATEWAY_NUM" -eq 1 || add_default_route
    sleep "$PING_INTERVAL"
done
