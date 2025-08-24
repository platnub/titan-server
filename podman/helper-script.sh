#!/bin/bash

# Configuration
base_dir="/home/podman/containers"
rootless_user=""  # Will be loaded from .env if available

# Colors for better visual feedback
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
NC='\033[0m' # No Color

# Function to display a header
display_header() {
    clear
    echo -e "${BLUE}======================================================"
    echo -e "  Podman Container Management Tool"
    echo -e "======================================================${NC}"
    echo
}

# Function to display a success message
success_msg() {
    echo -e "${GREEN}[✓] $1${NC}"
}

# Function to display an error message
error_msg() {
    echo -e "${RED}[✗] $1${NC}" >&2
}

# Function to display a warning message
warning_msg() {
    echo -e "${YELLOW}[!] $1${NC}"
}

# Function to display an info message
info_msg() {
    echo -e "${BLUE}[i] $1${NC}"
}

# Function to display a critical warning message
critical_warning() {
    echo -e "${MAGENTA}======================================================"
    echo -e "  ${RED}WARNING: $1${NC}"
    echo -e "======================================================${NC}"
}

# Function to prompt for confirmation with warning styling
confirm_warning() {
    local message=$1
    local default=${2:-n}  # Default to 'n' (no) if not specified

    while true; do
        echo -e "${MAGENTA}======================================================"
        echo -e "  ${RED}WARNING: $message${NC}"
        echo -e "======================================================${NC}"
        read -p "Are you sure? [y/N]: " -n 1 -r
        echo
        case $REPLY in
            [yY]) return 0 ;;
            [nN]|"") return 1 ;;
            *) warning_msg "Please answer yes or no." ;;
        esac
    done
}

# Function to prompt for confirmation
confirm() {
    while true; do
        read -p "$1 [y/n]: " -n 1 -r
        echo
        case $REPLY in
            [yY]) return 0 ;;
            [nN]) return 1 ;;
            *) warning_msg "Please answer yes or no." ;;
        esac
    done
}

# Function to check if a container exists by name
container_exists() {
    local container_name=$1

    # Check if the container exists by name (not image name)
    if podman ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        return 0  # Container exists
    else
        return 1  # Container does not exist
    fi
}

# Function to check if a container directory exists
container_dir_exists() {
    local container_name=$1

    if [ -d "$base_dir/$container_name" ]; then
        return 0  # Directory exists
    else
        return 1  # Directory does not exist
    fi
}

# Function to list all containers
list_containers() {
    display_header
    info_msg "Listing all Podman containers:"
    echo
    podman ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}"
    echo
}

# Function to wait for container to be fully running
wait_for_container_running() {
    local container_name=$1
    local max_attempts=60  # Increased timeout
    local attempt=0
    local status
    local health_status

    info_msg "Waiting for container $container_name to be fully running..."

    while [ $attempt -lt $max_attempts ]; do
        # Get container status
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
        if [ "$status" = "running" ]; then
            # Check if the container has a health check
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ -n "$health_status" ] && [ "$health_status" != "healthy" ]; then
                # If there's a health check but it's not healthy yet
                info_msg "Container $container_name is running but health check is $health_status..."
            else
                # Either no health check or it's healthy
                success_msg "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            error_msg "Container $container_name is in $status state."
            # Get exit code for more detailed error
            exit_code=$(podman inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null)
            if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
                error_msg "Container exited with code $exit_code"
                warning_msg "Container logs:"
                podman logs "$container_name" 2>&1
            fi
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    error_msg "Timeout waiting for container $container_name to start."
    info_msg "Current status: $status"
    warning_msg "Container logs:"
    podman logs "$container_name" 2>&1
    return 1
}

# Function to run a container
start_container() {
    local container_name=$1
    local result=0

    display_header
    info_msg "Starting container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        return 1
    fi

    reapply_permissions "$container_name"

    # Start the container
    info_msg "Starting container $container_name..."
    podman start "$container_name"

    # Wait for the container to be fully running
    if ! wait_for_container_running "$container_name"; then
        error_msg "Container $container_name did not start properly."
        result=1

        if confirm "Would you like to view the logs?"; then
            podman logs "$container_name" 2>&1
        fi

        if confirm "Would you like to attempt to restart the container?"; then
            info_msg "Attempting to restart container $container_name..."
            podman restart "$container_name"

            # Wait again
            if ! wait_for_container_running "$container_name"; then
                error_msg "Container $container_name failed to start after restart."
                result=1
            else
                result=0
            fi
        fi
    else
        update_rootless_user "$container_name"
        success_msg "Container $container_name started successfully."
    fi

    return $result
}

# Function to stop a container
stop_container() {
    local container_name=$1
    local result=0

    display_header
    info_msg "Stopping container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        return 1
    fi

    # Only update .env if this was called from option 3 in the menu
    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi

    if podman stop "$container_name"; then
        success_msg "Container $container_name stopped successfully."
    else
        error_msg "Failed to stop container $container_name."
        result=1
    fi

    return $result
}

# Function to create new folders in appdata
create_appdata_folders() {
    local container_name=$1
    local appdata_dir="$base_dir/$container_name/appdata"
    local result=0

    info_msg "Checking for new folders to create in $appdata_dir..."

    while true; do
        read -p "Enter a folder name to create in appdata (leave empty to finish): " folder_name
        if [[ -z "$folder_name" ]]; then
            break
        fi

        # Create the folder
        if sudo mkdir -p "$appdata_dir/$folder_name"; then
            success_msg "Created folder: $appdata_dir/$folder_name"

            # Apply permissions
            sudo chmod 700 "$appdata_dir/$folder_name"

            # If rootless_user is set, apply it
            if [ -n "$rootless_user" ]; then
                podman unshare chown "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"
                success_msg "Applied permissions for user $rootless_user"
            fi
        else
            error_msg "Failed to create folder $appdata_dir/$folder_name"
            result=1
        fi
    done

    return $result
}

# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1
    local result=0

    display_header
    info_msg "Decomposing container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        return 1
    fi

    if podman-compose --file "$base_dir/$container_name/compose.yaml" down; then
        success_msg "Container $container_name decomposed successfully."
    else
        error_msg "Failed to decompose container $container_name."
        result=1
    fi

    return $result
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    local result=0

    display_header
    info_msg "Composing container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        return 1
    fi

    update_rootless_user "$container_name"
    reapply_permissions "$container_name"

    if podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach; then
        success_msg "Container $container_name composed successfully."
    else
        error_msg "Failed to compose container $container_name."
        result=1
    fi

    return $result
}

# Function to recompose a container (decompose and then compose)
recompose_container() {
    local container_name=$1
    local result=0

    display_header
    info_msg "Recomposing container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        return 1
    fi

    if ! decompose_container "$container_name"; then
        result=1
    fi

    if ! compose_container "$container_name"; then
        result=1
    fi

    return $result
}

# Function to create a new container
create_container() {
    local container_name=$1
    local result=0

    display_header
    info_msg "Creating new container: $container_name"

    # Check if container already exists by name
    if container_exists "$container_name"; then
        error_msg "A container with the name '$container_name' already exists."
        return 1
    fi

    # Check if container directory already exists
    if container_dir_exists "$container_name"; then
        error_msg "A directory for container '$container_name' already exists at $base_dir/$container_name."
        if confirm "Would you like to overwrite the existing directory?"; then
            if ! sudo rm -rf "$base_dir/$container_name"; then
                error_msg "Failed to remove existing directory. Aborting."
                return 1
            fi
            success_msg "Removed existing directory for container '$container_name'."
        else
            warning_msg "Container creation cancelled."
            return 1
        fi
    fi

    # Create container directories
    if sudo mkdir -p "$base_dir/$container_name"; then
        success_msg "Created base directory: $base_dir/$container_name"
    else
        error_msg "Failed to create base directory."
        return 1
    fi

    if sudo mkdir -p "$base_dir/$container_name/appdata"; then
        success_msg "Created appdata directory"
    else
        error_msg "Failed to create appdata directory."
        result=1
    fi

    if sudo mkdir -p "$base_dir/$container_name/logs"; then
        success_msg "Created logs directory"
    else
        error_msg "Failed to create logs directory."
        result=1
    fi

    if sudo mkdir -p "$base_dir/$container_name/secrets"; then
        success_msg "Created secrets directory"
    else
        error_msg "Failed to create secrets directory."
        result=1
    fi

    # Create compose.yaml
    info_msg "Creating compose.yaml file..."
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"

    # Create .env file
    info_msg "Creating .env file..."
    sudo sh -c "echo -e \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"

    # Ask to create new folders in appdata
    if confirm "Do you want to create any new folders in the appdata directory?"; then
        if ! create_appdata_folders "$container_name"; then
            result=1
        fi
    fi

    reapply_permissions "$container_name"

    if [ $result -eq 0 ]; then
        success_msg "Container $container_name created successfully."

        # Ask to run the container
        if confirm "Do you want to compose the container now?"; then
            if ! compose_container "$container_name"; then
                result=1
            fi
        fi
    else
        error_msg "Container creation completed with errors."
    fi

    return $result
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1
    local result=0

    display_header
    info_msg "Applying permissions for container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        return 1
    fi

    # Set directory permissions
    if sudo chmod 700 "$base_dir/$container_name"; then
        success_msg "Set permissions for base directory"
    else
        error_msg "Failed to set permissions for base directory"
        result=1
    fi

    if sudo chmod 700 "$base_dir/$container_name/appdata"; then
        success_msg "Set permissions for appdata directory"
    else
        error_msg "Failed to set permissions for appdata directory"
        result=1
    fi

    if sudo chmod 700 "$base_dir/$container_name/logs"; then
        success_msg "Set permissions for logs directory"
    else
        error_msg "Failed to set permissions for logs directory"
        result=1
    fi

    if sudo chmod 400 "$base_dir/$container_name/secrets"; then
        success_msg "Set permissions for secrets directory"
    else
        error_msg "Failed to set permissions for secrets directory"
        result=1
    fi

    if sudo chmod 400 "$base_dir/$container_name/compose.yaml"; then
        success_msg "Set permissions for compose.yaml"
    else
        error_msg "Failed to set permissions for compose.yaml"
        result=1
    fi

    if sudo chmod 400 "$base_dir/$container_name/.env"; then
        success_msg "Set permissions for .env file"
    else
        error_msg "Failed to set permissions for .env file"
        result=1
    fi

    # Change ownership to podman user
    if sudo chown -R podman:podman "$base_dir/$container_name"; then
        success_msg "Changed ownership to podman user"
    else
        error_msg "Failed to change ownership to podman user"
        result=1
    fi

    # Load rootless_user if it exists
    if [ -f "$base_dir/$container_name/.env" ]; then
        if load_rootless_user "$container_name"; then
            if [ -n "$rootless_user" ]; then
                # Use podman unshare to change ownership inside the container's user namespace
                if podman unshare chown -R "$rootless_user:$rootless_user" "$base_dir/$container_name/appdata/"; then
                    success_msg "Applied permissions for user $rootless_user"
                else
                    error_msg "Failed to apply permissions for user $rootless_user"
                    result=1
                fi
            fi
        else
            result=1
        fi
    fi

    if [ $result -eq 0 ]; then
        success_msg "Permissions applied successfully."
    else
        error_msg "Permission application completed with errors."
    fi

    return $result
}

# Load rootless_user from .env
load_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    local result=0

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
    success_msg "Loaded rootless_user: $rootless_user"

    return $result
}

# Function to update rootless_user in .env
update_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    local result=0

    # Get HUSER for user "abc"
    local podman_huser
    podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')

    if [ -z "$podman_huser" ]; then
        error_msg "Could not determine HUSER for user 'abc' in container '$container_name'. Is it running and does user exist?"
        return 1
    fi

    if [ -e "$env_file" ]; then
        # Check if file is writable, if not make it writable temporarily
        if [ ! -w "$env_file" ]; then
            sudo chmod u+w "$env_file"
        fi

        if grep -qE '^[[:space:]]*rootless_user=' "$env_file"; then
            # Update existing key
            if sudo sed -i -E "s|^[[:space:]]*rootless_user=.*|rootless_user=$podman_huser|" "$env_file"; then
                success_msg "Updated rootless_user in .env"
            else
                error_msg "Failed to update rootless_user in .env"
                result=1
            fi
        else
            # Append the key
            if sudo sh -c "printf '\nrootless_user=%s\n' '$podman_huser' >> '$env_file'"; then
                success_msg "Added rootless_user to .env"
            else
                error_msg "Failed to add rootless_user to .env"
                result=1
            fi
        fi

        # Restore original permissions if we changed them
        if [ ! -w "$env_file" ]; then
            sudo chmod u-w "$env_file"
        fi
    else
        # Create new file with the key
        if sudo sh -c "printf 'rootless_user=%s\n' '$podman_huser' > '$env_file'"; then
            success_msg "Created .env with rootless_user"
        else
            error_msg "Failed to create .env with rootless_user"
            result=1
        fi
    fi

    return $result
}

# Function to remove a container
remove_container() {
    local container_name=$1
    local result=0

    display_header

    # First confirmation
    if ! confirm_warning "You are about to remove the container '$container_name'"; then
        warning_msg "Container removal cancelled."
        return 1
    fi

    info_msg "Removing container: $container_name"

    # Check if container exists
    if ! container_exists "$container_name"; then
        error_msg "Container $container_name does not exist."
        return 1
    fi

    # Stop the container first
    if ! stop_container "$container_name"; then
        result=1
    fi

    # Remove the container
    if podman rm "$container_name"; then
        success_msg "Container $container_name removed."
    else
        error_msg "Failed to remove container $container_name."
        result=1
    fi

    # Decompose the container
    if ! decompose_container "$container_name"; then
        result=1
    fi

    # Ask to remove ALL container data
    if confirm_warning "You are about to remove ALL DATA for container '$container_name'"; then
        if confirm_warning "THIS WILL PERMANENTLY DELETE ALL DATA FOR '$container_name' INCLUDING CONFIGURATION FILES, APPLICATION DATA, AND LOGS"; then
            if sudo rm -rf "$base_dir/$container_name"; then
                success_msg "ALL container data removed from $container_name."
            else
                error_msg "Failed to remove container data."
                result=1
            fi
        else
            warning_msg "Container data removal cancelled."
        fi
    else
        warning_msg "Container data removal cancelled."
    fi

    if [ $result -eq 0 ]; then
        success_msg "Container $container_name removed successfully."
    else
        error_msg "Container removal completed with errors."
    fi

    return $result
}

# Main menu
while true; do
    display_header
    echo -e "${YELLOW}Main Menu${NC}"
    echo "1. List all containers"
    echo "2. Start a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "5. Compose a container"
    echo "6. Recompose a container"
    echo "7. Apply permissions to a container"
    echo "8. Update rootless user"
    echo "99. Remove a container"
    echo "0. Exit"
    echo
    read -p "Enter your choice: " choice

    case $choice in
        1)
            list_containers
            read -p "Press Enter to continue..."
            ;;
        2)
            read -p "Enter the container name to start: " container_name
            start_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        3)
            read -p "Enter the container name to stop: " container_name
            stop_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        4)
            read -p "Enter the new container name: " container_name
            create_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        5)
            read -p "Enter the container name to compose: " container_name
            compose_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        6)
            read -p "Enter the container name to recompose: " container_name
            recompose_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        7)
            read -p "Enter the container name to apply permissions: " container_name
            reapply_permissions "$container_name"
            read -p "Press Enter to continue..."
            ;;
        8)
            read -p "Enter the container name to update rootless user: " container_name
            update_rootless_user "$container_name"
            read -p "Press Enter to continue..."
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        0)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            error_msg "Invalid choice. Please enter a valid option."
            read -p "Press Enter to continue..."
            ;;
    esac
done
