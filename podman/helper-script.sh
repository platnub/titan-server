#!/bin/bash

# Configuration
base_dir="/home/podman/containers"
rootless_user=""
container_name=""

# Color definitions for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display header
display_header() {
    clear
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}        PODMAN CONTAINER MANAGEMENT${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo ""
}

# Function to display footer
display_footer() {
    echo ""
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${YELLOW}Press [Enter] to continue...${NC}"
    read -r
}

# Function to display error message
display_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Function to display success message
display_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Function to display warning message
display_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Function to display info message
display_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

# Function to get yes/no confirmation
get_confirmation() {
    local prompt="$1"
    local default="${2:-n}"

    while true; do
        read -p "$prompt [y/n] (default: $default): " choice
        choice="${choice:-$default}"

        case "$choice" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) display_error "Please answer y or n." ;;
        esac
    done
}

# Function to list all containers
list_containers() {
    display_header
    echo -e "${BLUE}Listing all Podman containers:${NC}"
    echo "----------------------------------------------"
    podman ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"
    display_footer
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
        # Get container status
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)

        if [ "$status" = "running" ]; then
            # Check if the container has a health check
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)

            if [ -n "$health_status" ]; then
                if [ "$health_status" = "healthy" ]; then
                    display_success "Container $container_name is running and healthy."
                    return 0
                else
                    display_info "Container $container_name is running but health check is $health_status..."
                fi
            else
                # No health check defined, just check if it's running
                display_success "Container $container_name is running."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            display_error "Container $container_name is in $status state."
            # Get exit code for more detailed error
            exit_code=$(podman inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null)
            if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
                display_error "Container exited with code $exit_code"
                echo "Container logs:"
                podman logs "$container_name" 2>&1
            fi
            return 1
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    display_error "Timeout waiting for container $container_name to start."
    display_info "Current status: $status"
    echo "Container logs:"
    podman logs "$container_name" 2>&1
    return 1
}

# Function to run a container
start_container() {
    local container_name=$1
    display_header

    reapply_permissions "$container_name"

    # Start the container
    display_info "Starting container $container_name..."
    podman start "$container_name"

    # Wait for the container to be fully running
    if ! wait_for_container_running "$container_name"; then
        display_error "Container $container_name did not start properly."

        # Try to restart the container if it failed
        display_info "Attempting to restart container $container_name..."
        podman restart "$container_name"

        # Wait again
        if ! wait_for_container_running "$container_name"; then
            display_error "Container $container_name failed to start after restart."
            display_footer
            return 1
        fi
    fi

    update_rootless_user "$container_name"
    display_success "Container $container_name started successfully."
    display_footer
}

# Function to stop a container
stop_container() {
    local container_name=$1
    display_header

    # Only update .env if this was called from option 3 in the menu
    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi

    display_info "Stopping container $container_name..."
    podman stop "$container_name"
    display_success "Container $container_name stopped successfully."
    display_footer
}

# Function to create new folders in appdata
create_appdata_folders() {
    local container_name=$1
    local appdata_dir="$base_dir/$container_name/appdata"

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
            podman unshare chown -R "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"
        fi
    done
}

# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1
    display_header

    # Update rootless_user in .env before decomposing
    update_rootless_user "$container_name"

    display_info "Decomposing container $container_name..."
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    display_success "Container $container_name decomposed successfully."
    display_footer
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    display_header

    display_info "Composing container $container_name..."
    reapply_permissions "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    update_rootless_user "$container_name"
    display_success "Container $container_name composed successfully."
    display_footer
}

# Function to create a new container
create_container() {
    local container_name=$1
    display_header

    # Create container directories
    display_info "Creating container directories..."
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"

    # Create compose.yaml
    display_info "Creating compose.yaml file..."
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"

    # Create .env file
    display_info "Creating .env file..."
    sudo sh -c "echo \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"

    # Ask to create new folders in appdata
    if get_confirmation "Do you want to create any new folders in the appdata directory?"; then
        create_appdata_folders "$container_name"
    fi

    reapply_permissions "$container_name"
    display_success "Container $container_name created successfully."

    # Ask to run the container
    if get_confirmation "Do you want to compose the container now?"; then
        compose_container "$container_name"
    fi

    display_footer
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1
    local container_dir="$base_dir/$container_name"
    display_info "Applying permissions to container $container_name..."

    # Set directory permissions (excluding appdata contents)
    sudo chmod 700 "$container_dir"
    sudo chmod 700 "$container_dir/appdata"
    sudo chmod 700 "$container_dir/logs"
    sudo chmod 400 "$container_dir/secrets"
    sudo chmod 400 "$container_dir/compose.yaml"
    sudo chmod 400 "$container_dir/.env"

    # Change ownership to podman user (only for container directories, not contents)
    sudo chown podman:podman "$container_dir"
    sudo chown podman:podman "$container_dir/appdata"
    sudo chown podman:podman "$container_dir/logs"
    sudo chown podman:podman "$container_dir/secrets"
    sudo chown podman:podman "$container_dir/compose.yaml"
    sudo chown podman:podman "$container_dir/.env"

    # Load rootless_user if it exists
    if [ -f "$container_dir/.env" ]; then
        load_rootless_user "$container_name"
        if [ -n "$rootless_user" ]; then
            # Apply permissions to appdata directory itself (not contents)
            sudo chmod 700 "$container_dir/appdata"

            # Use podman unshare to change ownership of appdata directory itself
            podman unshare chown "$rootless_user:$rootless_user" "$container_dir/appdata"

            # If there are any existing files/directories in appdata, we should preserve their permissions
            # but we won't modify them recursively as requested
        fi
    fi

    display_success "Permissions applied successfully."
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
}

# Function to remove a container
remove_container() {
    local container_name=$1
    display_header

    # Confirm removal
    if ! get_confirmation "Are you sure you want to remove container $container_name?"; then
        display_info "Container removal cancelled."
        display_footer
        return 0
    fi

    # Stop the container first
    stop_container "$container_name"

    # Remove the container
    display_info "Removing container $container_name..."
    podman rm "$container_name"

    # Decompose the container
    decompose_container "$container_name"

    # Ask to remove ALL container data
    if get_confirmation "Do you want to remove ALL container data from $container_name?"; then
        display_warning "WARNING: This will permanently delete all files for $container_name!"
        display_warning "This action cannot be undone!"

        if get_confirmation "Are you ABSOLUTELY sure you want to delete ALL files for $container_name?" "n"; then
            sudo rm -rf "$base_dir/$container_name"
            display_success "ALL container data removed from $container_name."
        else
            display_info "Container data preservation confirmed."
        fi
    else
        display_info "Container data preservation confirmed."
    fi

    display_success "Container $container_name removed successfully."
    display_footer
}

# Function to edit container files with ranger
edit_container_files() {
    local container_name=$1
    local container_dir="$base_dir/$container_name"

    # Check if ranger is installed
    if ! command -v ranger &> /dev/null; then
        display_warning "Ranger is not installed. Would you like to install it now?"

        if get_confirmation "Install ranger from official repository?"; then
            # Update and upgrade system
            display_info "Updating system packages..."
            sudo apt-get update -y
            sudo apt-get upgrade -y

            # Install dependencies
            display_info "Installing required dependencies..."
            sudo apt-get install -y git python3 python3-pip python3-dev

            # Install ranger from official repository
            display_info "Installing ranger from official repository..."
            git clone https://github.com/ranger/ranger.git /tmp/ranger
            cd /tmp/ranger || exit 1
            sudo make install

            if [ $? -ne 0 ]; then
                display_error "Failed to install ranger. Please install it manually from https://github.com/ranger/ranger"
                display_footer
                return 1
            fi

            # Clean up
            cd ~ || exit 1
            rm -rf /tmp/ranger
        else
            display_info "Ranger is required to edit files. Please install it manually from https://github.com/ranger/ranger"
            display_footer
            return 1
        fi
    fi

    # Check if container directory exists
    if [ ! -d "$container_dir" ]; then
        display_error "Container directory $container_dir does not exist."
        display_footer
        return 1
    fi

    # Display instructions
    display_header
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}          RANGER FILE NAVIGATION${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo ""
    echo -e "${YELLOW}Instructions:${NC}"
    echo "1. Use arrow keys to navigate files and directories"
    echo "2. Press [Enter] to open files or directories"
    echo "3. Press [i] to edit files (will open in default editor)"
    echo "4. Press [m] to create new files or directories"
    echo "5. Press [dd] to delete files or directories"
    echo "6. Press [q] to quit ranger"
    echo ""
    echo -e "${BLUE}You are now in the container directory: $container_dir${NC}"
    echo -e "${YELLOW}Press [Enter] to start ranger...${NC}"
    read -r

    # Launch ranger in the container directory
    ranger "$container_dir"

    display_success "File editing session completed."
    display_footer
}

# Main menu
while true; do
    display_header
    echo -e "${BLUE}MAIN MENU${NC}"
    echo "----------------------------------------------"
    echo "1. List all containers"
    echo "2. Start a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "5. Compose a container"
    echo "6. Decompose a container"
    echo "7. Edit container files with ranger"
    echo "8. Remove a container"
    echo "9. Exit"
    echo "----------------------------------------------"
    read -p "Enter your choice (1-9): " choice

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
            read -p "Enter the container name to edit files: " container_name
            edit_container_files "$container_name"
            ;;
        8)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            ;;
        9)
            display_header
            echo -e "${GREEN}Exiting... Goodbye!${NC}"
            exit 0
            ;;
        *)
            display_error "Invalid choice. Please enter a number between 1 and 9."
            display_footer
            ;;
    esac
done
