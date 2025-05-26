#!/usr/bin/env bash

set -uo pipefail
IFS=$'\n'

INSTANCE=""
ROUTE_THROUGH_PROXYCHAINS=false
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
declare -A SERVER_LIST

exceptions() {
    throw_argument_exception() {
        echo -e "ERROR: Unrecognized argument.\nTry \`${0##*/} -h\` for more information." >&2
        exit 1
    }
    throw_env_file_exception() {
        echo -e "ERROR: Environment file does not exist.\nRead \`README.md\` for more information." >&2
        exit 1
    }
    throw_option_exception() {
        echo -e "ERROR: Unrecognized option.\nTry \`${0##*/} -h\` for more information." >&2
        exit 1
    }
}
exceptions

load_server_data() {
    if [ ! -f "$SCRIPT_PATH/servers.csv" ]; then
        echo -e "Server list not found.\nTemplate generated at '$SCRIPT_PATH/servers.csv'" >&2
        echo -e "Name,IP,User,Password,Description,Port" > "$SCRIPT_PATH/servers.csv"
        exit 0
    else
        while IFS=',' read -r name ip user password description port; do
            [ "$name" == "Name" ] && continue
            SERVER_LIST["$name"]="$ip,$user,$password,$description,$port"
        done < "$SCRIPT_PATH/servers.csv"
    fi
}

conveniences() {
    change_prompt_color() {
        declare -A colors=(
            ["Red"]='31'
            ["Green"]='32'
            ["Yellow"]='33'
            ["Blue"]='34'
            ["Magenta"]='35'
            ["Cyan"]='36'
            ["White"]='37'
        )
        if [ -z "$1" ]; then
            color_key="$(echo -e "${!colors[*]}" | dmenu -i -p "Pick a prompt color:")"
            case "${color_key,,}" in
                "") return 1 ;;
            esac
        else
            color_key="$1"
        fi
        xdotool type "export PS1='\e[1;${colors[$color_key]}m\u@\h\e[0m \w\n\$ '"
        sleep 0.1
        xdotool key "Enter"
        return 0
    }

    enter_password() {
        confirmation="$(echo -e "Confirm\nCancel" | dmenu -p "Auto type password?")"
        case "${confirmation,,}" in
            cancel | "") return 1 ;;
        esac
        xdotool type "$1"
        xdotool key "Enter"
        return 0
    }

    escalate_to_superuser() {
        confirmation="$(echo -e "Confirm\nCancel" | dmenu -p "Escalate to super user?")"
        case "${confirmation,,}" in
            cancel | "") return 1 ;;
        esac
        xdotool type "sudo su"
        sleep 0.1
        xdotool key "Enter"
        sleep 0.5
        xdotool type "$1"
        sleep 0.1
        xdotool key "Enter"
        return 0
    }

    clear_screen() {
        xdotool type "clear -x"
        sleep 0.1
        xdotool key "Enter"
        return 0
    }
}
conveniences

get_field() {
    local column_index="$1"
    awk -F ',' "{ print \$$column_index }" <<< "${SERVER_LIST[$INSTANCE]}"
}

select_instance() {
    INSTANCE="$(fzf <<< "${!SERVER_LIST[@]}")"
    [ -z "$INSTANCE" ] && return 1
    return 0
}

connect() {
    port="$(get_field 5)"
    (
        enter_password "$(get_field 3)" &&
            escalate_to_superuser "$(get_field 3)" &&
            sleep 0.1 &&
            change_prompt_color "White" &&
            sleep 0.1 &&
            clear_screen
    ) &
    if "$ROUTE_THROUGH_PROXYCHAINS"; then
        proxychains ssh -p "${port:=22}" "$(get_field 2)@$(get_field 1)"
    else
        ssh -p "${port:=22}" "$(get_field 2)@$(get_field 1)"
    fi
}

describe_and_copy_ip() {
    echo -e "\e[1m$INSTANCE\e[0m"
    IP="$(get_field 1)"
    echo -e "\e[1mDescription:\e[0m $(get_field 4)"
    [ -n "$IP" ] && echo -e "\e[1mIP:\e[0m $IP"
    get_field 1 | tr -d '\n' | xclip -selection clipboard
}

clear_clipboard() {
    (
        sleep 10
        xclip -selection clipboard < /dev/null
    ) &
    disown
}

copy_password() {
    trap clear_clipboard EXIT
    get_field 3 | tr -d '\n' | xclip -selection clipboard
}

documentation() {
    tabular_print() {
        counter=0
        result=""
        for el in "$@"; do
            ((counter++))
            result+="$el"
            [ $((counter % 2)) -ne 0 ] && result+="\t" || result+="\n"
        done
        echo -e "$result" | awk -v n=4 '{printf "%*s%s\n", n, "", $0}' | column -t -s $'\t'
    }
    cat << EOF
USAGE
    ${0##*/} [OPTIONS] [ARGUMENTS]
OPTIONS
$(
        tabular_print \
            "-c | --connect" "Connects to selected instance through SSH" \
            "-x | --connect-proxied" "Connects to selected instance through SSH over proxychains" \
            "-p | --password" "Copies password of selected instance to clipboard" \
            "-d | --describe" "Provides a description of selected instance" \
            "-d | --describe" "Provides a description of selected instance" \
            "-t | --execute-convenience" "Executes convenience of choice" \
            "-h | --help" "Shows this help message and exits"
    )
EOF
}

parse_options() {
    OPTS="$(getopt -o c,x,d,p,h,t -l route-through-proxy,connect,describe,password,execute-convenience,help -- "$@" 2> /dev/null)"
    [ $? -ne 0 ] && throw_option_exception
    eval set -- "$OPTS"
    while true; do
        case "$1" in
            -x | --connect-proxied)
                ROUTE_THROUGH_PROXYCHAINS=true
                load_server_data
                select_instance &&
                    connect
                exit 0
                ;;
            -c | --connect)
                load_server_data
                select_instance &&
                    connect
                exit 0
                ;;
            -d | --describe)
                load_server_data
                select_instance &&
                    describe_and_copy_ip
                exit 0
                ;;
            -p | --password)
                load_server_data
                select_instance &&
                    copy_password
                exit 0
                ;;
            -t | --execute-convenience)
                conveniences="$(echo -e "Change prompt color\nEnter password\nEscalate to superuser" | nl | fzf -m --prompt "Choose a convencience to execute: " --with-nth 2..)"
                mapfile -t conveniences_indices < <(awk '{print $1}' <<< "$conveniences")
                for convenience_idx in "${conveniences_indices[@]}"; do
                    case $convenience_idx in
                        1) change_prompt_color "" ;;
                        2)
                            load_server_data
                            select_instance &&
                                enter_password "$(get_field 3)"
                            ;;
                        3)
                            load_server_data
                            select_instance &&
                                escalate_to_superuser "$(get_field 3)"
                            ;;
                    esac
                done
                exit 0
                ;;
            -h | --help)
                documentation
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *) throw_option_exception ;;
        esac
    done
}

parse_options "$@"
