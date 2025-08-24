#!/bin/bash

# Configuration
base_dir="/home/podman/containers"
rootless_user=""
current_container=""

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display header
display_header() {
    clear
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}        PODMAN CONTAINER MANAGEMENT          ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo ""
}

# Function to display menu
display_menu() {
    display_header
    echo -e "${GREEN}1.${NC} List all containers"
    echo -e "${GREEN}2.${NC} Start a container"
    echo -e "${GREEN}3.${NC} Stop a container"
    echo -e "${GREEN}4.${NC} Create a new container"
    echo -e "${GREEN}5.${NC} Compose a container"
    echo -e "${GREEN}6.${NC} Decompose a container"
    echo -e "${GREEN}7.${NC} Edit container files"
    echo -e "${GREEN}8.${NC} Remove a container"
    echo -e "${GREEN}9.${NC} Exit"
    echo ""
}

# Function to pause and wait for user input
pause() {
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
}

# Function to display error message
error_msg() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Function to display warning message
warning_msg() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Function to display success message
success_msg() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Function to display info message
info_msg() {
    echo -e "${BLUE}INFO: $1${NC}"
}

# Function to list all containers
list_containers() {
    display_header
    echo -e "${BLUE}Listing all Podman containers:${NC}"
    echo "----------------------------------------"
    podman ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
    pause
}

# Function to wait for container to be fully running
wait_for_container_running() {
    local container_name=$1
    local max_attempts=60
    local attempt=0
    local status
    local health_status

    info_msg "Waiting for container $container_name to be fully running..."

    while [ $attempt -lt $max_attempts ]; do
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
        if [ "$status" = "running" ]; then
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ -n "$health_status" ] && [ "$health_status" != "healthy" ]; then
                info_msg "Container $container_name is running but health check is $health_status..."
            else
                success_msg "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            error_msg "Container $container_name is in $status state."
            exit_code=$(podman inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null)
            if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
                error_msg "Container exited with code $exit_code"
                echo "Container logs:"
                podman logs "$container_name" 2>&1
            fi
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    error_msg "Timeout waiting for container $container_name to start."
    echo "Current status: $status"
    echo "Container logs:"
    podman logs "$container_name" 2>&1
    return 1
}

# Function to start a container
start_container() {
    local container_name=$1
    display_header

    if [ -z "$container_name" ]; then
        read -p "Enter the container name to start: " container_name
    fi

    if ! podman container exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        pause
        return 1
    fi

    reapply_permissions "$container_name"

    info_msg "Starting container $container_name..."
    podman start "$container_name"

    if ! wait_for_container_running "$container_name"; then
        error_msg "Container $container_name did not start properly."
        echo "Container logs:"
        podman logs "$container_name" 2>&1

        warning_msg "Attempting to restart container $container_name..."
        podman restart "$container_name"

        if ! wait_for_container_running "$container_name"; then
            error_msg "Container $container_name failed to start after restart."
            pause
            return 1
        fi
    fi

    update_rootless_user "$container_name"
    success_msg "Container $container_name started successfully."
    pause
}

# Function to stop a container
stop_container() {
    local container_name=$1
    display_header

    if [ -z "$container_name" ]; then
        read -p "Enter the container name to stop: " container_name
    fi

    if ! podman container exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        pause
        return 1
    fi

    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi

    info_msg "Stopping container $container_name..."
    podman stop "$container_name"
    success_msg "Container $container_name stopped successfully."
    pause
}

# Function to create new folders in appdata
create_appdata_folders() {
    local container_name=$1
    local appdata_dir="$base_dir/$container_name/appdata"

    info_msg "Checking for new folders to create in $appdata_dir..."

    while true; do
        read -p "Enter a folder name to create in appdata (leave empty to finish): " folder_name
        if [[ -z "$folder_name" ]]; then
            break
        fi

        sudo mkdir -p "$appdata_dir/$folder_name"
        success_msg "Created folder: $appdata_dir/$folder_name"

        sudo chmod 700 "$appdata_dir/$folder_name"

        if [ -n "$rootless_user" ]; then
            podman unshare chown "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"
        fi
    done
}

# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1
    display_header

    if [ -z "$container_name" ]; then
        read -p "Enter the container name to decompose: " container_name
    fi

    if ! podman container exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        pause
        return 1
    fi

    info_msg "Decomposing container $container_name..."

    # Update rootless_user before decomposing
    update_rootless_user "$container_name"

    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    success_msg "Container $container_name decomposed successfully."
    pause
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    display_header

    if [ -z "$container_name" ]; then
        read -p "Enter the container name to compose: " container_name
    fi

    if ! podman container exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        pause
        return 1
    fi

    info_msg "Composing container $container_name..."

    update_rootless_user "$container_name"
    reapply_permissions "$container_name"

    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    success_msg "Container $container_name composed successfully."
    pause
}

# Function to create a new container
create_container() {
    local container_name=$1
    display_header

    if [ -z "$container_name" ]; then
        read -p "Enter the new container name: " container_name
    fi

    if [ -d "$base_dir/$container_name" ]; then
        error_msg "Container $container_name already exists."
        pause
        return 1
    fi

    info_msg "Creating container $container_name..."

    # Create container directories
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"

    # Create compose.yaml
    info_msg "Creating compose.yaml file..."
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"

    # Create .env file
    info_msg "Creating .env file..."
    sudo sh -c "echo -e \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"

    # Ask to create new folders in appdata
    read -p "Do you want to create any new folders in the appdata directory? (y/n): " create_folders
    if [[ "$create_folders" =~ ^[Yy]$ ]]; then
        create_appdata_folders "$container_name"
    fi

    reapply_permissions "$container_name"
    success_msg "Container $container_name created successfully."

    # Ask to run the container
    read -p "Do you want to compose the container now? (y/n): " compose_now
    if [[ "$compose_now" =~ ^[Yy]$ ]]; then
        compose_container "$container_name"
    fi

    pause
}

# Function to edit container files using ranger
edit_container_files() {
    local container_name=$1
    display_header

    if [ -z "$container_name" ]; then
        read -p "Enter the container name to edit files: " container_name
    fi

    if ! podman container exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        pause
        return 1
    fi

    # Check if ranger is installed
    if ! command -v ranger &> /dev/null; then
        warning_msg "Ranger is not installed. Installing now..."

        # Update and upgrade system
        sudo apt-get update && sudo apt-get upgrade -y

        # Install ranger
        sudo apt-get install -y ranger

        if ! command -v ranger &> /dev/null; then
            error_msg "Failed to install ranger. Please install it manually."
            pause
            return 1
        fi

        success_msg "Ranger installed successfully."
    fi

    # Set the current container for reference
    current_container="$container_name"

    # Display instructions
    display_header
    echo -e "${BLUE}RANGER FILE NAVIGATOR INSTRUCTIONS${NC}"
    echo "----------------------------------------"
    echo "1. Use arrow keys to navigate files and directories"
    echo "2. Press 'Enter' to open a file or directory"
    echo "3. Press 'i' to view file information"
    echo "4. Press 'e' to edit a file (uses your default editor)"
    echo "5. Press 'c' to create a new file"
    echo "6. Press 'd' to delete a file or directory"
    echo "7. Press 'q' to quit ranger"
    echo ""
    echo "You are currently editing files for container: ${GREEN}$container_name${NC}"
    echo "All changes will be made to: ${GREEN}$base_dir/$container_name${NC}"
    echo ""

    pause

    # Launch ranger in the container's directory
    ranger "$base_dir/$container_name"

    success_msg "File editing session completed for container $container_name."
    pause
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1

    info_msg "Applying permissions for container $container_name..."

    # Set directory permissions
    sudo chmod 700 "$base_dir/$container_name"
    sudo chmod 700 "$base_dir/$container_name/appdata"
    sudo chmod 700 "$base_dir/$container_name/logs"
    sudo chmod 400 "$base_dir/$container_name/secrets"
    sudo chmod 400 "$base_dir/$container_name/compose.yaml"
    sudo chmod 400 "$base_dir/$container_name/.env"

    # Change ownership to podman user
    sudo chown -R podman:podman "$base_dir/$container_name"

    # Load rootless_user if it exists
    if [ -f "$base_dir/$container_name/.env" ]; then
        load_rootless_user "$container_name"
        if [ -n "$rootless_user" ]; then
            podman unshare chown -R "$rootless_user:$rootless_user" "$base_dir/$container_name/appdata/"
        fi
    fi

    success_msg "Permissions applied successfully."
}

# Load rootless_user from .env
load_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"

    if [[ ! -r "$env_file" ]]; then
        error_msg "Cannot read $env_file"
        return 1
    fi

    # Get the line rootless_user=...
    local line
    line=$(sudo grep -m1 -E '^[[:space:]]*rootless_user[[:space:]]*=' "$env_file") || {
        error_msg "rootless_user not found in $env_file"
        return 1
    }

    # Extract value, strip inline comments/whitespace and surrounding quotes
    local val=${line#*=}
    val=${val%%#*}
    val=$(printf '%s\n' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    val=$(printf '%s\n' "$val" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")

    if [[ -z "$val" ]]; then
        error_msg "rootless_user value is empty in $env_file"
        return 1
    fi

    rootless_user="$val"
    export rootless_user
}

# Function to update rootless_user in .env
update_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"

    # Get HUSER for user "abc"
    local podman_huser
    podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')

    if [ -z "$podman_huser" ]; then
        warning_msg "Could not determine HUSER for user 'abc' in container '$container_name'. Is it running and does user exist?"
        return 1
    fi

    if [ -e "$env_file" ]; then
        # Check if file is writable, if not make it writable temporarily
        if [ ! -w "$env_file" ]; then
            sudo chmod u+w "$env_file"
        fi

        if grep -qE '^[[:space:]]*rootless_user=' "$env_file"; then
            # Update existing key
            sudo sed -i -E "s|^[[:space:]]*rootless_user=.*|rootless_user=$podman_huser|" "$env_file"
        else
            # Append the key
            sudo sh -c "printf '\nrootless_user=%s\n' '$podman_huser' >> '$env_file'"
        fi

        # Restore original permissions if we changed them
        if [ ! -w "$env_file" ]; then
            sudo chmod u-w "$env_file"
        fi
    else
        # Create new file with the key
        sudo sh -c "printf 'rootless_user=%s\n' '$podman_huser' > '$env_file'"
    fi

    success_msg "Updated rootless_user in .env"
}

# Function to remove a container
remove_container() {
    local container_name=$1
    display_header

    if [ -z "$container_name" ]; then
        read -p "Enter the container name to remove: " container_name
    fi

    if ! podman container exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        pause
        return 1
    fi

    warning_msg "You are about to remove container $container_name."
    read -p "Are you sure you want to continue? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info_msg "Container removal cancelled."
        pause
        return 0
    fi

    # Stop the container first
    stop_container "$container_name"

    # Remove the container
    podman rm "$container_name"

    # Decompose the container
    decompose_container "$container_name"

    # Ask to remove ALL container data
    read -p "Do you want to remove ALL container data from $container_name? (y/n): " remove_container_data
    if [[ "$remove_container_data" =~ ^[Yy]$ ]]; then
        read -p "!! Are you sure you want to remove ALL container data from $container_name? !! (y/n): " remove_container_data_sure
        if [[ "$remove_container_data_sure" =~ ^[Yy]$ ]]; then
            sudo rm -rf "$base_dir/$container_name"
            success_msg "ALL container data removed from $container_name."
        fi
    fi

    success_msg "Container $container_name removed successfully."
    pause
}

# Main program loop
while true; do
    display_menu
    read -p "Enter your choice (1-9): " choice

    case $choice in
        1)
            list_containers
            ;;
        2)
            start_container ""
            ;;
        3)
            stop_container ""
            ;;
        4)
            create_container ""
            ;;
        5)
            compose_container ""
            ;;
        6)
            decompose_container ""
            ;;
        7)
            edit_container_files ""
            ;;
        8)
            remove_container ""
            ;;
        9)
            echo -e "${BLUE}Exiting...${NC}"
            exit 0
            ;;
        *)
            error_msg "Invalid choice. Please enter a number between 1 and 9."
            pause
            ;;
    esac
done
