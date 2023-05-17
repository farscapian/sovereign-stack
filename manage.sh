#!/bin/bash

# https://www.sovereign-stack.org/ss-manage/

set -exu
cd "$(dirname "$0")"

# check to ensure dependencies are met.
if ! command -v lxc >/dev/null 2>&1; then
    echo "This script requires 'lxd/lxc' to be installed. Please run 'install.sh'."
    exit 1
fi

if ! lxc remote get-default | grep -q "local"; then
    lxc remote switch "local"
fi

if ! lxc list -q --format csv | grep -q ss-mgmt; then
    echo "ERROR: the 'ss-mgmt' VM does not exist. You may need to run install.sh"
    exit 1
fi

# if the mgmt machine doesn't exist, then warn the user to perform ./install.sh
if ! lxc list --format csv | grep -q "ss-mgmt"; then
    echo "ERROR: the management machine VM does not exist. You probably need to run './install.sh'."
    echo "INFO: check out https://www.sovereign-stack.org/tag/code-lifecycle-management/ for more information."
fi

# if the machine does exist, let's make sure it's RUNNING.
if lxc list --format csv | grep -q "ss-mgmt,STOPPED"; then
    echo "INFO: The SSME was in a STOPPED state. Starting the environment. Please wait."
    lxc start ss-mgmt
    sleep 30
fi

. ./management/wait_for_lxc_ip.sh

# let's ensure ~/.ssh/ssh_config is using the correct IP address for ss-mgmt.
ssh ubuntu@"$IP_V4_ADDRESS"
