#!/bin/sh
# VPN connection test client for bash.ws.
# Project: https://github.com/macvk/vpnleaktest
# SPDX-License-Identifier: MIT

version='1.0.0'

quote_argument() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

program_name=${0##*/}
case $0 in
    /*) script_path=$0 ;;
    */*) script_path=$(cd "${0%/*}" && pwd)/$program_name ;;
    *)
        script_path=$(command -v "$0" 2>/dev/null)
        [ -n "$script_path" ] || script_path=$(pwd)/$0
        ;;
esac
command_line=$(quote_argument "$program_name")

for argument do
    command_line="${command_line} $(quote_argument "$argument")"
done

RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'
api_domain='bash.ws'
error_code=1

interface=''
verbose=''
log_file=''
probes=30
parallel=30
timeout=90
short_output=0
watch_interval=''
watch_enabled=0
details_route=''
details_id=''

usage() {
    cat <<EOF
Usage: ${program_name} [OPTIONS]

Options:
  -i, --interface NAME|IP  Use a specific network interface
  -p, --probes NUMBER      Number of DNS probes to send (default: 30)
  -j, --parallel NUMBER    Maximum simultaneous probes (default: 30)
  -t, --timeout SECONDS    Maximum time for each request (default: 90)
  -s, --short              Print a one-line result
  -w, --watch [SECONDS]    Repeat continuously (default interval: 0)
  -v, --verbose LEVEL      Write diagnostics: info or trace
      --log-file FILE      Set the log path (implies --verbose info)
  -h, --help               Show this help
      --dnsleak TEST_ID    Show an existing DNS leak test result
      --openport TEST_ID   Show an existing open-port test result
      --blacklist TEST_ID  Show an existing blacklist test result
EOF
}

argument_error() {
    printf '%s\n' "$1" >&2
    printf "%s\n" "Try '${program_name} --help' for more information." >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -i|--interface)
            [ "$#" -ge 2 ] || argument_error "Option $1 requires a value."
            interface=$2
            shift 2
            ;;
        -v|--verbose)
            [ "$#" -ge 2 ] || argument_error "Option $1 requires info or trace."
            verbose=$2
            shift 2
            ;;
        -p|--probes)
            [ "$#" -ge 2 ] || argument_error "Option $1 requires a number."
            probes=$2
            shift 2
            ;;
        -j|--parallel)
            [ "$#" -ge 2 ] || argument_error "Option $1 requires a number."
            parallel=$2
            shift 2
            ;;
        -t|--timeout)
            [ "$#" -ge 2 ] || argument_error "Option $1 requires a number."
            timeout=$2
            shift 2
            ;;
        -s|--short)
            short_output=1
            shift
            ;;
        -w|--watch)
            watch_enabled=1
            watch_interval=0
            short_output=1
            shift

            if [ "$#" -gt 0 ]; then
                case "$1" in
                    -*) ;;
                    *)
                        watch_interval=$1
                        shift
                        ;;
                esac
            fi
            ;;
        --log-file)
            [ "$#" -ge 2 ] || argument_error "Option --log-file requires a path."
            log_file=$2
            shift 2
            ;;
        --dnsleak|--openport|--blacklist)
            [ "$#" -ge 2 ] || argument_error "Option $1 requires a test ID."
            [ -z "$details_route" ] || argument_error "Choose only one detail option."
            case "$1" in
                --dnsleak) details_route='/dnsleak' ;;
                --openport) details_route='/open-port-check' ;;
                --blacklist) details_route='/ip-blacklist-check' ;;
            esac
            details_id=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            [ "$#" -eq 0 ] || argument_error "Unexpected argument: $1"
            ;;
        -*)
            argument_error "Unknown option: $1"
            ;;
        *)
            argument_error "Unexpected argument: $1"
            ;;
    esac
done

case "$verbose" in
    ''|info|trace)
        ;;
    *)
        argument_error "Invalid verbosity level '$verbose'; expected info or trace."
        ;;
esac

case "$probes" in
    ''|*[!0-9]*)
        argument_error "Invalid probe count '$probes'; expected an integer from 1 to 100."
        ;;
esac

if [ "$probes" -lt 1 ] || [ "$probes" -gt 100 ]; then
    argument_error "Invalid probe count '$probes'; expected an integer from 1 to 100."
fi

case "$parallel" in
    ''|*[!0-9]*)
        argument_error "Invalid parallel count '$parallel'; expected an integer from 1 to 100."
        ;;
esac

if [ "$parallel" -lt 1 ] || [ "$parallel" -gt 100 ]; then
    argument_error "Invalid parallel count '$parallel'; expected an integer from 1 to 100."
fi

case "$timeout" in
    ''|*[!0-9]*)
        argument_error "Invalid timeout '$timeout'; expected an integer from 10 to 300."
        ;;
esac

if [ "$timeout" -lt 10 ] || [ "$timeout" -gt 300 ]; then
    argument_error "Invalid timeout '$timeout'; expected an integer from 10 to 300."
fi

if [ "$watch_enabled" -eq 1 ]; then
    case "$watch_interval" in
        ''|*[!0-9]*)
            argument_error "Invalid watch interval '$watch_interval'; expected zero or a positive number of seconds."
            ;;
    esac
fi
[ -z "$log_file" ] || [ -n "$verbose" ] || verbose='info'

if [ -n "$verbose" ]; then
    if [ -z "$log_file" ]; then
        case "$(uname -s 2>/dev/null)" in
            Darwin)
                log_file="${HOME}/Library/Logs/vpnleaktest/vpnleaktest.log"
                ;;
            *)
                log_file="${XDG_STATE_HOME:-${HOME}/.local/state}/vpnleaktest/vpnleaktest.log"
                ;;
        esac
    fi

    log_dir=${log_file%/*}
    [ "$log_dir" = "$log_file" ] && log_dir='.'
    umask 077

    if ! mkdir -p "$log_dir" || ! : >> "$log_file" || ! chmod 600 "$log_file"; then
        argument_error "Cannot create diagnostic log: $log_file"
    fi

    if [ "${VPNLEAK_WATCH_CHILD:-0}" != 1 ]; then
        printf 'Diagnostic log: %s\n' "$log_file"
    fi
fi

log_info() {
    [ -z "$verbose" ] ||
        printf '%s [INFO] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$log_file"
}

log_trace() {
    [ "$verbose" != trace ] ||
        printf '%s [TRACE] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$log_file"
}

log_info "${program_name} version ${version} started; OS=$(uname -s 2>/dev/null); interface=${interface:-default}; probes=$probes; parallel=$parallel"
log_info "Command line: ${command_line}"

echo_bold() {
    printf '%b\n' "${BOLD}${1}${NC}"
    log_info "$1"
}

print_line() {
    printf '%s\n' "$1"
    log_info "$1"
}

if [ -n "$interface" ]; then
    echo_bold "Interface: ${interface}"
    printf '\n'
fi

increment_error_code() {
    error_code=$((error_code + 1))
}

echo_error() {
    printf '%b\n' "${RED}${1}${NC}" >&2
    log_info "ERROR: $1"
    log_info "vpnleaktest finished; exit=$error_code"
}

require_command() {
    if ! command -v "$1" > /dev/null 2>&1; then
        echo_error "Please, install \"$1\""
        exit "$error_code"
    fi
    increment_error_code
}

curl_request() {
    if [ "$verbose" = trace ]; then
        log_trace "curl request started"
        if [ -n "$interface" ]; then
            curl --verbose --max-time "$timeout" --interface "$interface" "$@" 2>> "$log_file"
        else
            curl --verbose --max-time "$timeout" "$@" 2>> "$log_file"
        fi
        status=$?
        log_trace "curl request finished; exit=$status"
        return "$status"
    fi
    if [ -n "$log_file" ] && [ -n "$interface" ]; then
        curl --max-time "$timeout" --interface "$interface" "$@" 2>> "$log_file"
    elif [ -n "$log_file" ]; then
        curl --max-time "$timeout" "$@" 2>> "$log_file"
    elif [ -n "$interface" ]; then
        curl --max-time "$timeout" --interface "$interface" "$@"
    else
        curl --max-time "$timeout" "$@"
    fi
}

ping_request() {
    if [ "$verbose" = trace ]; then
        trace_output=${probe_trace_file:-$log_file}
        printf '%s [TRACE] ping %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$trace_output"
    else
        trace_output=/dev/null
    fi
    if [ -n "$interface" ]; then
        if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
            case "$interface" in
                *:*|*[0-9].[0-9]*)
                    ping -S "$interface" "$@" >> "$trace_output" 2>&1
                    ;;
                *)
                    ping -b "$interface" "$@" >> "$trace_output" 2>&1
                    ;;
            esac
        else
            ping -I "$interface" "$@" >> "$trace_output" 2>&1
        fi
    else
        ping "$@" >> "$trace_output" 2>&1
    fi
}

check_internet_connection() {
    log_info "Checking connectivity to ${api_domain}"
    if ! curl_request --silent --show-error --fail --head --output /dev/null "https://${api_domain}"; then
        echo_error "No internet connection."
        exit "$error_code"
    fi
    increment_error_code
}

json_record() {
    json=$1
    type=$2

    if command -v jq > /dev/null 2>&1; then
        printf '%s\n' "$json" | jq --raw-output --arg type "$type" '.[] | select(.type == $type) | .text // empty'
        return
    fi

    printf '%s\n' "$json" | sed 's/},{/}\
{/g' | sed -n "/\"type\"[[:space:]]*:[[:space:]]*\"${type}\"/s/.*\"text\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

run_test() {
    name=$1
    shift

    if ! test_json=$(curl_request --silent --show-error --fail "$@"); then
        echo_error "Unable to complete the ${name} check."
        exit "$error_code"
    fi

    case $(printf '%s' "$test_json" | sed 's/^[[:space:]]*//;s/\(.\).*/\1/') in
        '[') ;;
        *)
            echo_error "Invalid response from the ${name} check."
            exit "$error_code"
            ;;
    esac

    test_error=$(json_record "$test_json" error)
    if [ -n "$test_error" ]; then
        echo_error "$test_error"
        exit "$error_code"
    fi
}

start_test() {
    name=$1
    path=$2

    if ! start_json=$(curl_request --silent --show-error --fail --request POST "https://${api_domain}${path}"); then
        echo_error "Unable to start the ${name} check."
        exit "$error_code"
    fi

    case "$start_json" in
        *'"done":1'*) ;;
        *)
            echo_error "Unable to start the ${name} check."
            exit "$error_code"
            ;;
    esac
}

require_command curl

if [ -n "$details_route" ]; then
    case "$details_id" in ''|*[!a-zA-Z0-9]*) argument_error "Invalid test ID." ;; esac
    details_query='embed=raw'
    [ "$details_route" = '/dnsleak' ] && details_query=raw
    curl_request --silent --show-error --fail "https://${api_domain}${details_route}/test/${details_id}?${details_query}"
    exit $?
fi

require_command ping
test_started=$(date +%s)
check_internet_connection

if ! id=$(curl_request --silent --show-error --fail "https://${api_domain}/id"); then
    echo_error "Unable to obtain a test ID from ${api_domain}."
    exit "$error_code"
fi

case "$id" in
    ????????????????) ;;
    *)
        echo_error "Invalid test ID returned by ${api_domain}."
        exit "$error_code"
        ;;
esac

case "$id" in
    *[!A-Za-z0-9]*)
        echo_error "Invalid test ID returned by ${api_domain}."
        exit "$error_code"
        ;;
esac

log_info "Test ID received; bytes=${#id}"
increment_error_code

ipv4=$(curl_request -4 --silent --show-error --fail "https://ipv4.${api_domain}/myip/test/${id}" 2>/dev/null || :)
ipv6=$(curl_request -6 --silent --show-error --fail "https://ipv6.${api_domain}/myip/test/${id}" 2>/dev/null || :)
case "$ipv4" in *.*.*.*) ;; *) ipv4='' ;; esac
case "$ipv6" in *:*) ;; *) ipv6='' ;; esac

i=1
active_probes=0
while [ "$i" -le "$probes" ]; do
    log_info "Starting DNS probe $i of $probes"
    if [ "$verbose" = trace ]; then
        probe_trace_file="${log_file}.probe-${i}.tmp" \
            ping_request -c 1 -W 1 "${i}.${id}.${api_domain}" > /dev/null 2>&1 &
    else
        ping_request -c 1 -W 1 "${i}.${id}.${api_domain}" > /dev/null 2>&1 &
    fi
    active_probes=$((active_probes + 1))
    if [ "$active_probes" -ge "$parallel" ]; then
        wait
        active_probes=0
    fi
    i=$((i + 1))
done
wait

if [ "$verbose" = trace ]; then
    i=1
    while [ "$i" -le "$probes" ]; do
        probe_trace_file="${log_file}.probe-${i}.tmp"
        if [ -f "$probe_trace_file" ]; then
            cat "$probe_trace_file" >> "$log_file"
            rm -f "$probe_trace_file"
        fi
        i=$((i + 1))
    done
fi

run_test DNS "https://${api_domain}/dnsleak/test/${id}?json=2"
start_test ports "/open-port-check/test/${id}"
run_test ports "https://${api_domain}/open-port-check/test/${id}?json"

if [ -n "$ipv4" ]; then
    start_test 'IPv4 blacklist' "/ip-blacklist-check/test/${id}/ipv4"
    run_test 'IPv4 blacklist' "https://${api_domain}/ip-blacklist-check/test/${id}/ipv4?json"
fi

if [ -n "$ipv6" ]; then
    start_test 'IPv6 blacklist' "/ip-blacklist-check/test/${id}/ipv6"
    run_test 'IPv6 blacklist' "https://${api_domain}/ip-blacklist-check/test/${id}/ipv6?json"
fi

final_format=json
[ "$short_output" -eq 1 ] || final_format=txt
if ! final_result=$(curl_request --silent --show-error --fail \
    "https://${api_domain}/vpn-leak-test/test/${id}?${final_format}"); then
    echo_error "Unable to retrieve the VPN connection result."
    exit "$error_code"
fi

if [ "$short_output" -eq 1 ]; then
    final_error=$(json_record "$final_result" error)
    if [ -n "$final_error" ]; then
        echo_error "$final_error"
        exit "$error_code"
    fi

    test_result=$(json_record "$final_result" conclusion)
    if [ -z "$test_result" ]; then
        echo_error "Invalid response from the VPN connection check."
        exit "$error_code"
    fi

    log_info "result=$test_result"
    test_finished=$(date +%s)
    print_line "$(date '+%Y-%m-%dT%H:%M:%S%z') $((test_finished - test_started))s $test_result"
else
    printf '%s\n' "$final_result"
    log_info "VPN connection result received"
fi

log_info "vpnleaktest finished; exit=0"
[ "$watch_enabled" -eq 1 ] || exit 0

[ "$watch_interval" -eq 0 ] || sleep "$watch_interval"
set -- -p "$probes" -j "$parallel" -t "$timeout" -w "$watch_interval"
[ -z "$interface" ] || set -- "$@" -i "$interface"
[ -z "$verbose" ] || set -- "$@" -v "$verbose"
[ -z "$log_file" ] || set -- "$@" --log-file "$log_file"
VPNLEAK_WATCH_CHILD=1
export VPNLEAK_WATCH_CHILD
exec "$script_path" "$@"
