#!/bin/bash
# Version: 0.0.1

# Define the SUPPLIER ID
AIRSHIP_SUPPLIER_ID=104650
# Define the URL for the Airship installation script
AIRSHIP_RUNNER_URL="https://infra-iaas-1312767721.cos.ap-shanghai.myqcloud.com/box-tools/install-on-systemd.sh"

export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/snap/bin

function check_multipass() {
    if command -v multipass &> /dev/null; then
        # Multipass is installed, output version info
        local multipass_version
        multipass_version=$(multipass --version)
        echo "Multipass is installed. Version info: $multipass_version"
    else
        # Multipass is not installed
        echo "Error: Multipass is not installed." >&2
        exit 1
    fi
}

# Function to create the VM
function create_vm() {
    check_multipass
    local VM_NAME="ubuntu-airship"
    local AIRSHIP_SUPPLIER_DEVICE_ID=TNT$(date +%y%m%d%H%M%S%3N)

    # Create the virtual machine with Multipass (Ubuntu by default)
    echo "Creating the virtual machine $VM_NAME..."
    multipass launch --name "$VM_NAME" --cpus 2 --memory 2G --disk 64G  -vvvv

    # Check if the VM creation was successful
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create VM $VM_NAME." >&2
        exit 1
    fi

    # Fetch the installation script
    echo "Fetching the installation script..."
    multipass exec "$VM_NAME" -- wget -q "$AIRSHIP_RUNNER_URL" -O /tmp/install-on-systemd.sh

    # Set the execute permission on the downloaded script with sudo
    multipass exec "$VM_NAME" -- sudo chmod +x /tmp/install-on-systemd.sh

    # Run the installation script inside the VM
    echo "Running airship inside the VM..."
    multipass exec "$VM_NAME" -- sudo DEVICE_CLASS=box DEVICE_SUPPLIER=$AIRSHIP_SUPPLIER_ID DEVICE_SUPPLIER_DEVICE_ID=$AIRSHIP_SUPPLIER_DEVICE_ID /tmp/install-on-systemd.sh install

    # Check if the script execution was successful
    if [[ $? -eq 0 ]]; then
        echo "The script has been executed successfully inside the VM."
    else
        echo "Error: Failed to execute script inside the VM." >&2
        exit 1
    fi

    local retry_count=0
    local max_retries=10
    local BOX_ID=""

    echo "Checking the status of airship-box-agent.service..."
    service_status=$(multipass exec "$VM_NAME" -- sudo systemctl is-active airship-box-agent.service)

    if [[ "$service_status" == "active" ]]; then
        echo "The airship-box-agent.service is running."
        while [[ $retry_count -lt $max_retries ]]; do
            # Try to read BOX_ID
            BOX_ID=$(multipass exec "$VM_NAME" -- cat /opt/.airship/id)
            if [[ -z "$BOX_ID" ]]; then
                echo "BOX_ID is not found. Retrying... (Attempt $((retry_count + 1)))"
            else
                echo "Successfully read BOX_ID: $BOX_ID"
                exit 0
            fi
            ((retry_count++))

            echo "Retrying in 3 seconds..."
            sleep 3
        done
    fi

    echo "airship-box-agent.service is not running."
    exit 1
    
}

function info() {
    # check_multipass
    local VM_NAME="ubuntu-airship"
    local BOX_ID
    BOX_ID=$(multipass exec "$VM_NAME" -- cat /opt/.airship/id)
    if [[ -z "$BOX_ID" ]]; then
        echo "Error: BOX_ID is not found." >&2
        exit 1
    fi
    echo "BOX_ID: $BOX_ID"
}

function reinstall() {
    local VM_NAME="ubuntu-airship"
    if multipass list | grep -q "$VM_NAME"; then
        echo "Deleting existing $VM_NAME VM..."
        multipass delete "$VM_NAME"
        multipass purge
    fi
    echo "Creating new Airship VM..."
    create_vm
    return $?
}

function restart() {
    local VM_NAME="ubuntu-airship"
    echo "Restarting service..."
    multipass restart "$VM_NAME"
}

function start() {
    local VM_NAME="ubuntu-airship"
    echo "Starting service..."
    multipass start "$VM_NAME"
}

function stop() {
    local VM_NAME="ubuntu-airship"
    echo "Stopping service..."
    multipass stop "$VM_NAME"
}


function delete() {
    local VM_NAME="ubuntu-airship"
    echo "Deleting service..."
    multipass delete "$VM_NAME"
    multipass purge
}

function status() {
    local VM_NAME="ubuntu-airship"
    local vm_status
    vm_status=$(multipass list | grep "$VM_NAME" | awk '{print $2}')
    if [[ -z "$vm_status" ]]; then
        echo "STATUS: none"
    elif [[ "$vm_status" == "Running" ]]; then
        echo "STATUS: running"
    elif [[ "$vm_status" == "Stopped" ]]; then
        echo "STATUS: stopped"
    else
        echo "STATUS: unknown"
    fi
}

function main() {
    case $1 in
        install)
            create_vm
            ;;
        info)
            info
            ;;
        reinstall)
            reinstall
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        restart)
            restart
            ;;
        delete)
            delete
            ;;
        status)
            status
            ;;
        *)
            echo "Usage: $0 {install|reinstall|restart|delete|stop|status|info}" >&2
            exit 1
            ;;
    esac
}

main "$@"