#!/bin/bash

# Configuration
base_dir="/home/podman/containers"
rootless_user=""
current_container=""

# Color definitions for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display colored messages
display_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to display error messages
display_error() {
    display_message "${RED}" "[ERROR] $1"
}

# Function to display success messages
display_success() {
    display_message "${GREEN}" "[SUCCESS] $1"
}

# Function to display warning messages
display_warning() {
    display_message "${YELLOW}" "[WARNING] $1"
}

# Function to display info messages
display_info() {
    display_message "${BLUE}" "[INFO] $1"
}

# Function to pause and wait for user input
pause_for_input() {
    read -p "Press [Enter] to continue..."
}

# Function to list all containers
list_containers() {
    clear
    display_info "Listing all Podman containers:"
    echo "----------------------------------------"
    podman ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo "----------------------------------------"
    pause_for_input
}

# Function to wait for container to be fully running
wait_for_container_running() {
    local container_name=$1
    local max_attempts=60
    local attempt=0
    local status
    local health_status

    display_info "Waiting for container $container_name to be fully running..."

    while [ $attempt -lt $max_attempts ]; do
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
        if [ "$status" = "running" ]; then
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ -n "$health_status" ] && [ "$health_status" != "healthy" ]; then
                display_warning "Container $container_name is running but health check is $health_status..."
            else
                display_success "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            display_error "Container $container_name is in $status state."
            exit_code=$(podman inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null)
            if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
                display_error "Container exited with code $exit_code"
                display_info "Container logs:"
                podman logs "$container_name" 2>&1
            fi
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    display_error "Timeout waiting for container $container_name to start."
    display_info "Current status: $status"
    display_info "Container logs:"
    podman logs "$container_name" 2>&1
    return 1
}

# Function to run a container
start_container() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Starting container $container_name..."

    reapply_permissions "$container_name"

    # Start the container
    podman start "$container_name"

    # Wait for the container to be fully running
    if ! wait_for_container_running "$container_name"; then
        display_error "Container $container_name did not start properly."

        # Check container logs for errors
        display_info "Container logs:"
        podman logs "$container_name" 2>&1

        # Try to restart the container if it failed
        display_info "Attempting to restart container $container_name..."
        podman restart "$container_name"

        # Wait again
        if ! wait_for_container_running "$container_name"; then
            display_error "Container $container_name failed to start after restart."
            pause_for_input
            return 1
        fi
    fi

    update_rootless_user "$container_name"
    display_success "Container $container_name started successfully."
    pause_for_input
}

# Function to stop a container
stop_container() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Stopping container $container_name..."

    # Only update .env if this was called from option 3 in the menu
    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi

    podman stop "$container_name"
    display_success "Container $container_name stopped successfully."
    pause_for_input
}

# Function to create new folders in appdata
create_appdata_folders() {
    local container_name=$1
    local appdata_dir="$base_dir/$container_name/appdata"

    clear
    display_info "Checking for new folders to create in $appdata_dir..."

    while true; do
        read -p "Enter a folder name to create in appdata (leave empty to finish): " folder_name
        if [[ -z "$folder_name" ]]; then
            break
        fi

        # Create the folder
        sudo mkdir -p "$appdata_dir/$folder_name"
        display_success "Created folder: $appdata_dir/$folder_name"

        # Apply permissions
        sudo chmod 700 "$appdata_dir/$folder_name"

        # If rootless_user is set, apply it
        if [ -n "$rootless_user" ]; then
            podman unshare chown "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"
        fi
    done
}

# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Decomposing container $container_name..."

    # Update rootless_user before decomposing
    update_rootless_user "$container_name"

    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    display_success "Container $container_name decomposed successfully."
    pause_for_input
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Composing container $container_name..."

    update_rootless_user "$container_name"
    reapply_permissions "$container_name"

    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    display_success "Container $container_name composed successfully."
    pause_for_input
}

# Function to recompose a container (decompose and then compose)
recompose_container() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Recomposing container $container_name..."

    decompose_container "$container_name"
    compose_container "$container_name"

    display_success "Container $container_name recomposed successfully."
    pause_for_input
}

# Function to edit files using Rancher
edit_files_with_rancher() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Preparing to edit files for container $container_name..."

    # Check if Rancher is installed
    if ! command -v rancher &> /dev/null; then
        display_warning "Rancher is not installed. Installing now..."

        # Update and upgrade system
        display_info "Updating system packages..."
        sudo apt-get update -y
        sudo apt-get upgrade -y

        # Install Rancher
        display_info "Installing Rancher..."
        sudo apt-get install -y rancher

        if ! command -v rancher &> /dev/null; then
            display_error "Failed to install Rancher. Please install it manually."
            pause_for_input
            return 1
        fi
    fi

    # Get container ID
    local container_id=$(podman ps -aqf "name=$container_name")
    if [ -z "$container_id" ]; then
        display_error "Container $container_name not found."
        pause_for_input
        return 1
    fi

    # Start Rancher with the container's filesystem
    display_info "Starting Rancher to edit files for container $container_name..."
    display_info "You can now navigate and edit files. Important commands:"
    display_info "- To create a new file: Press 'a' in normal mode, then type the filename"
    display_info "- To edit a file: Move cursor to file and press 'i' to enter insert mode"
    display_info "- To delete a file: Move cursor to file and press 'd' then 'd'"
    display_info "- To save changes: Press ':wq' in normal mode"
    display_info "- To quit without saving: Press ':q!' in normal mode"

    # Run Rancher with the container's root filesystem
    sudo rancher --container "$container_id" --root

    display_success "Finished editing files for container $container_name."
    pause_for_input
}

# Function to create a new container
create_container() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Creating new container: $container_name"

    # Create container directories
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"

    # Create compose.yaml
    display_info "Creating compose.yaml file..."
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"

    # Create .env file
    display_info "Creating .env file..."
    sudo sh -c "echo -e \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"

    # Ask to create new folders in appdata
    read -p "Do you want to create any new folders in the appdata directory? (y/n): " create_folders
    if [[ "$create_folders" =~ ^[Yy]$ ]]; then
        create_appdata_folders "$container_name"
    fi

    reapply_permissions "$container_name"
    display_success "Container $container_name created successfully."

    # Ask to run the container
    read -p "Do you want to compose the container now? (y/n): " compose_now
    if [[ "$compose_now" =~ ^[Yy]$ ]]; then
        compose_container "$container_name"
    fi

    pause_for_input
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1

    clear
    display_info "Applying permissions for container $container_name..."

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
            # Use podman unshare to change ownership inside the container's user namespace
            podman unshare chown -R "$rootless_user:$rootless_user" "$base_dir/$container_name/appdata/"
        fi
    fi

    display_success "Permissions applied successfully."
    pause_for_input
}

# Load rootless_user from .env
load_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"

    if [[ ! -r "$env_file" ]]; then
        display_error "Cannot read $env_file"
        return 1
    fi

    # Get the line rootless_user=...
    local line
    line=$(sudo grep -m1 -E '^[[:space:]]*rootless_user[[:space:]]*=' "$env_file") || {
        display_error "rootless_user not found in $env_file"
        return 1
    }

    # Extract value, strip inline comments/whitespace and surrounding quotes
    local val=${line#*=}
    val=${val%%#*}
    val=$(printf '%s\n' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    val=$(printf '%s\n' "$val" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")

    if [[ -z "$val" ]]; then
        display_error "rootless_user value is empty in $env_file"
        return 1
    fi

    rootless_user="$val"
    export rootless_user
}

# Function to update rootless_user in .env
update_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"

    clear
    display_info "Updating rootless_user for container $container_name..."

    # Get HUSER for user "abc"
    local podman_huser
    podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')

    if [ -z "$podman_huser" ]; then
        display_warning "Could not determine HUSER for user 'abc' in container '$container_name'. Is it running and does user exist?"
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

    display_success "Updated rootless_user in .env"
    pause_for_input
}

# Function to remove a container
remove_container() {
    local container_name=$1
    current_container="$container_name"

    clear
    display_info "Removing container $container_name..."

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
            display_success "ALL container data removed from $container_name."
        fi
    fi

    display_success "Container $container_name removed successfully."
    pause_for_input
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}   Podman Container Management Tool   ${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo -e "${GREEN}1. List all containers${NC}"
        echo -e "${GREEN}2. Start a container${NC}"
        echo -e "${GREEN}3. Stop a container${NC}"
        echo -e "${GREEN}4. Create a new container${NC}"
        echo -e "${GREEN}5. Compose a container${NC}"
        echo -e "${GREEN}6. Decompose a container${NC}"
        echo -e "${GREEN}7. Recompose a container${NC}"
        echo -e "${GREEN}8. Edit container files with Rancher${NC}"
        echo -e "${GREEN}9. Remove a container${NC}"
        echo -e "${RED}0. Exit${NC}"
        echo ""
        echo -e "${BLUE}Current container: ${current_container:-None}${NC}"
        echo -e "${BLUE}========================================${NC}"

        read -p "Enter your choice (0-9): " choice

        case $choice in
            1)
                list_containers
                ;;
            2)
                read -p "Enter the container name to start: " container_name
                start_container "$container_name"
                ;;
            3)
                read -p "Enter the container name to stop: " container_name
                stop_container "$container_name"
                ;;
            4)
                read -p "Enter the new container name: " container_name
                create_container "$container_name"
                ;;
            5)
                read -p "Enter the container name to compose: " container_name
                compose_container "$container_name"
                ;;
            6)
                read -p "Enter the container name to decompose: " container_name
                decompose_container "$container_name"
                ;;
            7)
                read -p "Enter the container name to recompose: " container_name
                recompose_container "$container_name"
                ;;
            8)
                read -p "Enter the container name to edit files: " container_name
                edit_files_with_rancher "$container_name"
                ;;
            9)
                read -p "Enter the container name to remove: " container_name
                remove_container "$container_name"
                ;;
            0)
                clear
                display_info "Exiting Podman Container Management Tool..."
                exit 0
                ;;
            *)
                display_error "Invalid choice. Please enter a number between 0 and 9."
                pause_for_input
                ;;
        esac
    done
}

# Start the application
main_menu
