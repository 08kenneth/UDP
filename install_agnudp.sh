#!/usr/bin/env bash
#
# Try `install_agnudp.sh --help` for usage.
#
# (c) 2023 Khaled AGN
#

set -e

# Domain Name
DOMAIN="vpn.khaledagn.com"

# PROTOCOL
PROTOCOL="udp"

# UDP PORT
UDP_PORT=":36712"

# OBFS
OBFS="agnudp"

# PASSWORDS
PASSWORD="agnudp"

# Script paths
SCRIPT_NAME="$(basename "$0")"
SCRIPT_ARGS=("$@")
EXECUTABLE_INSTALL_PATH="/usr/local/bin/hysteria"
SYSTEMD_SERVICES_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/hysteria"
USER_DB="$CONFIG_DIR/udpusers.db"
REPO_URL="https://github.com/apernet/hysteria"
CONFIG_FILE="$CONFIG_DIR/config.json"
API_BASE_URL="https://api.github.com/repos/apernet/hysteria"
CURL_FLAGS=(-L -f -q --retry 5 --retry-delay 10 --retry-max-time 60)
PACKAGE_MANAGEMENT_INSTALL="${PACKAGE_MANAGEMENT_INSTALL:-}"
SYSTEMD_SERVICE="$SYSTEMD_SERVICES_DIR/hysteria-server.service"
mkdir -p "$CONFIG_DIR"
touch "$USER_DB"

# Other configurations
OPERATING_SYSTEM=""
ARCHITECTURE=""
HYSTERIA_USER=""
HYSTERIA_HOME_DIR=""
VERSION=""
FORCE=""
LOCAL_FILE=""
FORCE_NO_ROOT=""
FORCE_NO_SYSTEMD=""

# Utility functions
has_command() {
    local _command=$1
    type -P "$_command" > /dev/null 2>&1
}

curl() {
    command curl "${CURL_FLAGS[@]}" "$@"
}

mktemp() {
    command mktemp "$@" "hyservinst.XXXXXXXXXX"
}

tput() {
    if has_command tput; then
        command tput "$@"
    fi
}

tred() {
    tput setaf 1
}

tgreen() {
    tput setaf 2
}

tyellow() {
    tput setaf 3
}

tblue() {
    tput setaf 4
}

taoi() {
    tput setaf 6
}

tbold() {
    tput bold
}

treset() {
    tput sgr0
}

note() {
    local _msg="$1"
    echo -e "$SCRIPT_NAME: $(tbold)note: $_msg$(treset)"
}

warning() {
    local _msg="$1"
    echo -e "$SCRIPT_NAME: $(tyellow)warning: $_msg$(treset)"
}

error() {
    local _msg="$1"
    echo -e "$SCRIPT_NAME: $(tred)error: $_msg$(treset)"
}

show_argument_error_and_exit() {
    local _error_msg="$1"
    error "$_error_msg"
    echo "Try \"$0 --help\" for the usage." >&2
    exit 22
}

install_content() {
    local _install_flags="$1"
    local _content="$2"
    local _destination="$3"

    local _tmpfile="$(mktemp)"

    echo -ne "Install $_destination ... "
    echo "$_content" > "$_tmpfile"
    if install "$_install_flags" "$_tmpfile" "$_destination"; then
        echo -e "ok"
    fi

    rm -f "$_tmpfile"
}

remove_file() {
    local _target="$1"

    echo -ne "Remove $_target ... "
    if rm "$_target"; then
        echo -e "ok"
    fi
}

exec_sudo() {
    local _saved_ifs="$IFS"
    IFS=$'\n'
    local _preserved_env=(
        $(env | grep "^PACKAGE_MANAGEMENT_INSTALL=" || true)
        $(env | grep "^OPERATING_SYSTEM=" || true)
        $(env | grep "^ARCHITECTURE=" || true)
        $(env | grep "^HYSTERIA_\w*=" || true)
        $(env | grep "^FORCE_\w*=" || true)
    )
    IFS="$_saved_ifs"

    exec sudo env \
    "${_preserved_env[@]}" \
    "$@"
}

install_software() {
    local package="$1"
    if has_command apt-get; then
        echo "Installing $package using apt-get..."
        apt-get update && apt-get install -y "$package"
    elif has_command dnf; then
        echo "Installing $package using dnf..."
        dnf install -y "$package"
    elif has_command yum; then
        echo "Installing $package using yum..."
        yum install -y "$package"
    elif has_command zypper; then
        echo "Installing $package using zypper..."
        zypper install -y "$package"
    elif has_command pacman; then
        echo "Installing $package using pacman..."
        pacman -Sy --noconfirm "$package"
    else
        echo "Error: No supported package manager found. Please install $package manually."
        exit 1
    fi
}

is_user_exists() {
    local _user="$1"
    id "$_user" > /dev/null 2>&1
}

check_permission() {
    if [[ "$UID" -eq '0' ]]; then
        return
    fi

    note "The user currently executing this script is not root."

    case "$FORCE_NO_ROOT" in
        '1')
            warning "FORCE_NO_ROOT=1 is specified, we will process without root and you may encounter the insufficient privilege error."
            ;;
        *)
            if has_command sudo; then
                note "Re-running this script with sudo, you can also specify FORCE_NO_ROOT=1 to force this script running with current user."
                exec_sudo "$0" "${SCRIPT_ARGS[@]}"
            else
                error "Please run this script with root or specify FORCE_NO_ROOT=1 to force this script running with current user."
                exit 13
            fi
            ;;
    esac
}

check_environment_operating_system() {
    if [[ -n "$OPERATING_SYSTEM" ]]; then
        warning "OPERATING_SYSTEM=$OPERATING_SYSTEM is specified, operating system detection will not be performed."
        return
    }

    if [[ "x$(uname)" == "xLinux" ]]; then
        OPERATING_SYSTEM=linux
        return
    }

    error "This script only supports Linux."
    note "Specify OPERATING_SYSTEM=[linux|darwin|freebsd|windows] to bypass this check and force this script running on this $(uname)."
    exit 95
}

check_environment_architecture() {
    if [[ -n "$ARCHITECTURE" ]]; then
        warning "ARCHITECTURE=$ARCHITECTURE is specified, architecture detection will not be performed."
        return
    }

    case "$(uname -m)" in
        'i386' | 'i686')
            ARCHITECTURE='386'
            ;;
        'amd64' | 'x86_64')
            ARCHITECTURE='amd64'
            ;;
        'armv5tel' | 'armv6l' | 'armv7' | 'armv7l')
            ARCHITECTURE='arm'
            ;;
        'armv8' | 'aarch64')
            ARCHITECTURE='arm64'
            ;;
        'mips' | 'mipsle' | 'mips64' | 'mips64le')
            ARCHITECTURE='mipsle'
            ;;
        's390x')
            ARCHITECTURE='s390x'
            ;;
        *)
            error "The architecture '$(uname -a)' is not supported."
            note "Specify ARCHITECTURE=<architecture> to bypass this check and force this script running on this $(uname -m)."
            exit 8
            ;;
    esac
}

check_environment_systemd() {
    if [[ -d "/run/systemd/system" ]] || grep -q systemd <(ls -l /sbin/init); then
        return
    }

    case "$FORCE_NO_SYSTEMD" in
        '1')
            warning "FORCE_NO_SYSTEMD=1 is specified, we will process as normal even if systemd is not detected by us."
            ;;
        '2')
            warning "FORCE_NO_SYSTEMD=2 is specified, we will process but all systemd related commands will not be executed."
            ;;
        *)
            error "This script only supports Linux distributions with systemd."
            note "Specify FORCE_NO_SYSTEMD=1 to bypass this check and force this script running without systemd detection."
            exit 99
            ;;
    esac
}

check_download() {
    local _url="$1"
    local _dest="$2"
    local _temp_file=$(mktemp)

    echo -ne "Downloading $_url ... "
    if curl -o "$_temp_file" "$_url"; then
        echo -e "ok"
        if [[ -f "$_dest" ]]; then
            diff "$_temp_file" "$_dest" > /dev/null 2>&1 || install_content "m" "$(< "$_temp_file")" "$_dest"
        else
            install_content "m" "$(< "$_temp_file")" "$_dest"
        fi
    else
        error "Failed to download $_url"
        exit 22
    fi

    rm -f "$_temp_file"
}

check_install() {
    if [[ ! -x "$EXECUTABLE_INSTALL_PATH" ]]; then
        note "Hysteria is not installed, will perform the installation."
        return 0
    fi

    local _ver_installed
    _ver_installed="$("$EXECUTABLE_INSTALL_PATH" -v 2>/dev/null | awk '{ print $2 }')"
    if [[ "$_ver_installed" == "$VERSION" ]]; then
        note "Hysteria v$VERSION is already installed."
        return 1
    fi

    return 0
}

do_install() {
    local _url
    _url=$(curl -s "$API_BASE_URL/releases/latest" | jq -r '.assets[] | select(.name | contains("linux-amd64")) | .browser_download_url')
    local _tmpfile
    _tmpfile="$(mktemp)"

    echo -ne "Downloading latest hysteria binary ... "
    curl -L -f -o "$_tmpfile" "$_url"
    echo -e "ok"

    echo -ne "Installing hysteria ... "
    chmod +x "$_tmpfile"
    mv "$_tmpfile" "$EXECUTABLE_INSTALL_PATH"
    echo -e "ok"
}

do_uninstall() {
    if [[ -x "$EXECUTABLE_INSTALL_PATH" ]]; then
        echo -ne "Removing hysteria ... "
        rm -f "$EXECUTABLE_INSTALL_PATH"
        echo -e "ok"
    else
        echo "Hysteria is not installed."
    fi
}

do_systemd() {
    echo -ne "Adding systemd service ... "
    cat <<EOF > "$SYSTEMD_SERVICE"
[Unit]
Description=Hysteria Server
After=network.target

[Service]
ExecStart=$EXECUTABLE_INSTALL_PATH -c $CONFIG_FILE
Restart=always
User=$(whoami)
Group=$(whoami)
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable hysteria-server.service
    systemctl start hysteria-server.service
    echo -e "ok"
}

do_config() {
    local _content
    _content=$(cat <<EOF
{
    "server": "$DOMAIN$UDP_PORT",
    "obfs": "$OBFS",
    "password": "$PASSWORD",
    "up": 100,
    "down": 100
}
EOF
)
    echo -ne "Configuring hysteria ... "
    install_content "m" "$_content" "$CONFIG_FILE"
    echo -e "ok"
}

do() {
    case "$1" in
        install)
            check_environment_operating_system
            check_environment_architecture
            check_environment_systemd
            check_permission
            check_install && do_install
            do_config
            do_systemd
            ;;
        uninstall)
            do_uninstall
            ;;
        *)
            show_argument_error_and_exit "Invalid argument '$1'"
            ;;
    esac
}

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTION...] {install|uninstall}

Install/uninstall hysteria server.

Options:
  --help          Display this help message and exit.
  --no-root       Skip root privilege check and proceed.
  --no-systemd    Skip systemd-related steps and proceed.

EOF
}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --help)
                show_help
                exit 0
                ;;
            --no-root)
                FORCE_NO_ROOT=1
                ;;
            --no-systemd)
                FORCE_NO_SYSTEMD=1
                ;;
            *)
                ;;
        esac
    done
}

parse_args "$@"
do "$1"
