#!/bin/bash
# Script: Podman Container Management
# Description: A comprehensive script to manage Podman containers with proper error handling and user feedback
# Author: [Your Name]
# Version: 1.0
# Base directory for all container data
base_dir="/opt/containers"
# Color definitions
RED='\033[1;31m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
# Function to display error messages in red
error_msg() {
    echo -e "${RED}[ERROR]${RESET} $1" >&2
}
# Function to display warning messages in yellow
warning_msg() {
    echo -e "${YELLOW}[WARNING]${RESET} $1"
}
# Function to display informational messages in green
info_msg() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}
# Function to display success messages in blue
success_msg() {
    echo -e "${BLUE}[SUCCESS]${RESET} $1"
}
# Function to display important messages in magenta
important_msg() {
    echo -e "${MAGENTA}[IMPORTANT]${RESET} $1"
}
# Function to display debug messages in cyan
debug_msg() {
    echo -e "${CYAN}[DEBUG]${RESET} $1"
}
# Function to display a separator line
separator() {
    echo -e "${WHITE}---------------------------------------------${RESET}"
}
# Function to display a header
header() {
    clear
    separator
    echo -e "${WHITE}${1}${RESET}"
    separator
}
# Function to list all containers and compare with directories
list_containers() {
    header "Listing All Podman Containers"
    info_msg "Retrieving container information..."
    echo ""

    # Get list of container directories
    container_dirs=()
    if [ -d "$base_dir" ]; then
        while IFS= read -r dir; do
            container_dirs+=("$dir")
        done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" 2>/dev/null)
    fi

    # Display running containers
    echo -e "${GREEN}Running Containers:${RESET}"
    podman ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}" || error_msg "Failed to list running containers."
    echo ""

    # Display stopped containers
    echo -e "${YELLOW}Stopped Containers:${RESET}"
    podman ps -a --filter "status=exited" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" || error_msg "Failed to list stopped containers."
    echo ""

    # Display created containers
    echo -e "${BLUE}Created Containers:${RESET}"
    podman ps -a --filter "status=created" --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" || error_msg "Failed to list created containers."
    echo ""

    # Compare container directories with actual containers
    echo -e "${MAGENTA}Container Directory Comparison:${RESET}"
    separator

    # Get list of container names from podman
    container_names=()
    while IFS= read -r name; do
        container_names+=("$name")
    done < <(podman ps -a --format "{{.Names}}" 2>/dev/null)

    # Check for directories without containers
    directories_without_containers=()
    for dir in "${container_dirs[@]}"; do
        if [[ ! " ${container_names[@]} " =~ " ${dir} " ]]; then
            directories_without_containers+=("$dir")
        fi
    done

    # Display directories without containers in red
    if [ ${#directories_without_containers[@]} -gt 0 ]; then
        echo -e "${RED}Directories without containers:${RESET}"
        for dir in "${directories_without_containers[@]}"; do
            echo -e "${RED}  - $dir${RESET}"
        done
        echo ""
    else
        echo -e "${GREEN}All container directories have corresponding containers.${RESET}"
        echo ""
    fi

    separator
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
                warning_msg "Container $container_name is running but health check is $health_status..."
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
                echo "Container logs:"
                podman logs "$container_name" 2>&1 || warning_msg "Could not retrieve container logs."
            fi
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    error_msg "Timeout waiting for container $container_name to start."
    echo "Current status: $status"
    echo "Container logs:"
    podman logs "$container_name" 2>&1 || warning_msg "Could not retrieve container logs."
    return 1
}
# Function to run a container
start_container() {
    local container_name=$1
    # Check if container exists
    if ! podman inspect "$container_name" &>/dev/null; then
        error_msg "Container $container_name does not exist."
        return 1
    fi
    reapply_permissions "$container_name" || {
        error_msg "Failed to reapply permissions for $container_name"
        return 1
    }
    # Start the container
    info_msg "Starting container $container_name..."
    if ! podman start "$container_name"; then
        error_msg "Failed to start container $container_name"
        return 1
    fi
    # Wait for the container to be fully running
    if ! wait_for_container_running "$container_name"; then
        error_msg "Container $container_name did not start properly."
        # Check container logs for errors
        echo "Container logs:"
        podman logs "$container_name" 2>&1 || warning_msg "Could not retrieve container logs."
        # Try to restart the container if it failed
        warning_msg "Attempting to restart container $container_name..."
        if ! podman restart "$container_name"; then
            error_msg "Failed to restart container $container_name"
            return 1
        fi
        # Wait again
        if ! wait_for_container_running "$container_name"; then
            error_msg "Container $container_name failed to start after restart."
            return 1
        fi
    fi
    update_rootless_user "$container_name" || warning_msg "Failed to update rootless user for $container_name"
    success_msg "Container $container_name started successfully."
}
# Function to stop a container
stop_container() {
    local container_name=$1
    # Check if container exists
    if ! podman inspect "$container_name" &>/dev/null; then
        error_msg "Container $container_name does not exist."
        return 1
    fi
    # Only update .env if this was called from option 3 in the menu
    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name" || warning_msg "Failed to update rootless user for $container_name"
    fi
    info_msg "Stopping container $container_name..."
    if ! podman stop "$container_name"; then
        error_msg "Failed to stop container $container_name"
        return 1
    fi
    success_msg "Container $container_name stopped successfully."
}
# Function to manage files (browse, edit, create, delete)
manage_files() {
    local container_name=$1
    local container_dir="$base_dir/$container_name"
    local current_dir="$container_dir"
    # Check if container exists
    if [ ! -d "$container_dir" ]; then
        error_msg "Container directory $container_dir does not exist."
        return 1
    fi
    # Check if nano is installed
    if ! command -v nano &> /dev/null; then
        warning_msg "nano is not installed. Please install it first."
        read -p "Do you want to install nano now? (y/n): " install_nano
        if [[ "$install_nano" =~ ^[Yy]$ ]]; then
            info_msg "Installing nano..."
            if ! (sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get install -y nano); then
                error_msg "Failed to install nano."
                return 1
            fi
            success_msg "nano installed successfully."
        else
            error_msg "Cannot proceed without nano. Exiting..."
            return 1
        fi
    fi
    while true; do
        header "File Manager - $container_name"
        echo -e "${GREEN}Current Directory:${RESET} $current_dir"
        separator
        echo -e "${GREEN}Files and Directories:${RESET}"
        separator
        # List files and directories with proper sudo for appdata
        if [[ "$current_dir" == *"appdata"* ]]; then
            local items=($(sudo ls -lA "$current_dir" 2>/dev/null | awk '{print $9}')) || {
                error_msg "Failed to list directory contents in $current_dir"
                break
            }
        else
            local items=($(ls -lA "$current_dir" 2>/dev/null | awk '{print $9}')) || {
                error_msg "Failed to list directory contents in $current_dir"
                break
            }
        fi
        # Display files and directories with / appended to directories
        for i in "${!items[@]}"; do
            local item="${items[$i]}"
            if [[ "$current_dir" == *"appdata"* ]]; then
                local item_type=$(sudo ls -ld "$current_dir/$item" 2>/dev/null | awk '{print $1}')
            else
                local item_type=$(ls -ld "$current_dir/$item" 2>/dev/null | awk '{print $1}')
            fi
            if [[ "$item_type" == d* ]]; then
                # It's a directory - append /
                echo -e "${BLUE}$((i + 1)). ${item}/${RESET}"
            else
                # It's a file
                echo -e "${WHITE}$((i + 1)). ${item}${RESET}"
            fi
        done
        separator
        echo -e "${GREEN}Options:${RESET}"
        separator
        echo -e "${WHITE}0. Go back to previous directory${RESET}"
        echo -e "${WHITE}c. Create new file${RESET}"
        echo -e "${WHITE}d. Delete file/directory${RESET}"
        echo -e "${WHITE}99. Exit file manager${RESET}"
        separator
        read -p "Enter your choice (1-${#items[@]}, 0, c, d, or 99): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -eq 0 ]; then
                if [ "$current_dir" != "$container_dir" ]; then
                    # Fix: Use dirname to properly handle path navigation
                    current_dir=$(dirname "$current_dir")
                    # Ensure we don't end up with double slashes
                    current_dir=${current_dir%/}
                else
                    warning_msg "Already at the root directory of the container."
                    sleep 2
                fi
            elif [ "$choice" -eq 99 ]; then
                break
            elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
                local selected_item=${items[$((choice - 1))]#* }
                # Check if the selected item is a directory
                if [[ "$current_dir" == *"appdata"* ]]; then
                    local item_type=$(sudo ls -ld "$current_dir/$selected_item" 2>/dev/null | awk '{print $1}')
                else
                    local item_type=$(ls -ld "$current_dir/$selected_item" 2>/dev/null | awk '{print $1}')
                fi
                if [[ "$item_type" == d* ]]; then
                    # It's a directory
                    if [[ "$current_dir/$selected_item" == *"appdata"* ]]; then
                        important_msg "WARNING: You are entering the appdata directory."
                        important_msg "This directory contains sensitive permissions. Be careful with your changes."
                        important_msg "This operation requires sudo rights."
                        read -p "Press Enter to continue or Ctrl+C to cancel..."
                    fi
                    # Fix: Ensure we don't add double slashes when concatenating paths
                    current_dir="${current_dir%/}/${selected_item}"
                else
                    # It's a file
                    # Fix: Ensure we don't add double slashes when opening files
                    local file_path="${current_dir%/}/${selected_item}"
                    info_msg "Opening $file_path with nano..."
                    if [[ "$current_dir" == *"appdata"* ]]; then
                        important_msg "WARNING: You are editing files in the appdata directory."
                        important_msg "This directory contains sensitive permissions. Be careful with your changes."
                        read -p "Press Enter to continue or Ctrl+C to cancel..."
                        sudo nano "$file_path" || error_msg "Failed to open file with nano."
                    else
                        sudo nano "$file_path" || error_msg "Failed to open file with nano."
                    fi
                fi
            else
                error_msg "Invalid choice. Please enter a valid number."
                sleep 2
            fi
        elif [[ "$choice" == "c" ]]; then
            read -p "Enter new file name: " new_file
            if [[ -n "$new_file" ]]; then
                # Fix: Ensure we don't add double slashes when creating files
                local file_path="${current_dir%/}/${new_file}"
                if [[ "$current_dir" == *"appdata"* ]]; then
                    important_msg "WARNING: You are creating a file in the appdata directory."
                    important_msg "This directory contains sensitive permissions. Be careful with your changes."
                    read -p "Press Enter to continue or Ctrl+C to cancel..."
                    if ! (sudo touch "$file_path" && sudo chmod 600 "$file_path"); then
                        error_msg "Failed to create file $file_path"
                        continue
                    fi
                    if [ -n "$rootless_user" ]; then
                        if ! podman unshare chown "$rootless_user:$rootless_user" "$file_path"; then
                            warning_msg "Failed to set ownership for $file_path"
                        fi
                    fi
                else
                    if ! touch "$file_path"; then
                        error_msg "Failed to create file $file_path"
                        continue
                    fi
                fi
                success_msg "File $file_path created."
                sleep 2
            fi
        elif [[ "$choice" == "d" ]]; then
            read -p "Enter file/directory name to delete: " delete_item
            if [[ -n "$delete_item" ]]; then
                # Fix: Ensure we don't add double slashes when deleting files
                local item_path="${current_dir%/}/${delete_item}"
                if [[ "$current_dir" == *"appdata"* ]]; then
                    important_msg "WARNING: You are deleting a file/directory in the appdata directory."
                    important_msg "This directory contains sensitive permissions. Be careful with your changes."
                    read -p "Press Enter to continue or Ctrl+C to cancel..."
                    if ! sudo rm -rf "$item_path"; then
                        error_msg "Failed to delete $item_path"
                        continue
                    fi
                else
                    if ! rm -rf "$item_path"; then
                        error_msg "Failed to delete $item_path"
                        continue
                    fi
                fi
                success_msg "Deleted $item_path"
                sleep 2
            fi
        else
            error_msg "Invalid input. Please enter a number, 'c', 'd', or '99'."
            sleep 2
        fi
    done
}
# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1
    # Check if container exists
    if ! podman inspect "$container_name" &>/dev/null; then
        error_msg "Container $container_name does not exist."
        return 1
    fi
    update_rootless_user "$container_name" || warning_msg "Failed to update rootless user for $container_name"
    info_msg "Decomposing container $container_name..."
    if ! podman-compose --file "$base_dir/$container_name/compose.yml" down; then
        error_msg "Failed to decompose container $container_name"
        return 1
    fi
    success_msg "Container $container_name decomposed successfully."
}
# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    # Check if container exists
    if [ ! -d "$base_dir/$container_name" ]; then
        error_msg "Container directory $base_dir/$container_name does not exist."
        return 1
    fi
    info_msg "Composing container $container_name..."
    reapply_permissions "$container_name" || {
        error_msg "Failed to reapply permissions for $container_name"
        return 1
    }
    if ! podman-compose --file "$base_dir/$container_name/compose.yml" up --detach; then
        error_msg "Failed to compose container $container_name"
        return 1
    fi
    # Wait for container to be running
    if ! wait_for_container_running "$container_name"; then
        error_msg "Container $container_name did not start properly after composition."
        return 1
    fi
    update_rootless_user "$container_name" || warning_msg "Failed to update rootless user for $container_name"
    success_msg "Container $container_name composed successfully."
}
# Function to create a new container
create_container() {
    local container_name=$1
    # Check if container already exists
    if [ -d "$base_dir/$container_name" ]; then
        warning_msg "Container directory $base_dir/$container_name already exists."
        read -p "Do you want to overwrite it? (y/n): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            info_msg "Container creation cancelled."
            return 1
        fi
    fi
    # Create container directories
    info_msg "Creating container directories..."
    if ! (sudo mkdir -p "$base_dir/$container_name" &&
          sudo mkdir -p "$base_dir/$container_name/appdata" &&
          sudo mkdir -p "$base_dir/$container_name/logs" &&
          sudo mkdir -p "$base_dir/$container_name/secrets"); then
        error_msg "Failed to create container directories"
        return 1
    fi
    # Create empty compose.yml file first
    info_msg "Creating empty compose.yml file..."
    if ! sudo touch "$base_dir/$container_name/compose.yml"; then
        error_msg "Failed to create empty compose.yml file"
        return 1
    fi

    # Edit compose.yml file
    info_msg "Editing compose.yml file..."
    if ! sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yml"; then
        error_msg "Failed to edit compose.yml file"
        return 1
    fi

    # Create .env file
    info_msg "Creating .env file..."
    if ! sudo sh -c "echo \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"; then
        error_msg "Failed to create .env file"
        return 1
    fi
    if ! sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"; then
        error_msg "Failed to edit .env file"
        return 1
    fi
    # Ask to create new folders in appdata
    read -p "Do you want to create any new folders in the appdata directory? (y/n): " create_folders
    if [[ "$create_folders" =~ ^[Yy]$ ]]; then
        create_appdata_folders "$container_name" || warning_msg "Failed to create appdata folders"
    fi
    reapply_permissions "$container_name" || {
        error_msg "Failed to reapply permissions for $container_name"
        return 1
    }
    success_msg "Container $container_name created successfully."
    # Ask to run the container
    read -p "Do you want to compose the container now? (y/n): " compose_now
    if [[ "$compose_now" =~ ^[Yy]$ ]]; then
        compose_container "$container_name" || error_msg "Failed to compose container $container_name"
    fi
}
# Apply user permissions
reapply_permissions() {
    local container_name=$1
    # Check if container directory exists
    if [ ! -d "$base_dir/$container_name" ]; then
        error_msg "Container directory $base_dir/$container_name does not exist."
        return 1
    fi
    info_msg "Applying permissions to container $container_name..."
    # Set directory permissions
    if ! (sudo chmod 700 "$base_dir/$container_name" &&
          sudo chmod 700 "$base_dir/$container_name/appdata" &&
          sudo chmod 700 "$base_dir/$container_name/logs" &&
          sudo chmod 400 "$base_dir/$container_name/secrets" &&
          sudo chmod 400 "$base_dir/$container_name/compose.yml" &&
          sudo chmod 400 "$base_dir/$container_name/.env"); then
        error_msg "Failed to set directory permissions"
        return 1
    fi
    # Change ownership to podman user
    if ! sudo chown -R podman:podman "$base_dir/$container_name"; then
        error_msg "Failed to change ownership to podman user"
        return 1
    fi
    # Load rootless_user if it exists
    if [ -f "$base_dir/$container_name/.env" ]; then
        load_rootless_user "$container_name" || warning_msg "Failed to load rootless user from .env"
        if [ -n "$rootless_user" ]; then
            # Use podman unshare to change ownership inside the container's user namespace
            if ! podman unshare chown -R "$rootless_user:$rootless_user" "$base_dir/$container_name/appdata/"; then
                warning_msg "Failed to set appdata ownership for rootless user"
            fi
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
    info_msg "Loaded rootless_user: $rootless_user"
}
# Function to update rootless_user in .env with retry logic
update_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    local max_retries=5
    local retry_delay=1
    local retry_count=0
    local podman_huser
    # First check if container is running
    if ! podman ps -l | grep -q "$container_name"; then
        error_msg "Container $container_name is not running. Cannot update rootless_user."
        return 1
    fi
    info_msg "Updating rootless_user for container $container_name..."
    while [ $retry_count -lt $max_retries ]; do
        # Get HUSER for user "root"
        podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="root" {print $2; exit}')
        if [ -n "$podman_huser" ]; then
            break
        fi
        warning_msg "Attempt $((retry_count + 1)): Could not determine HUSER for user 'root' in container '$container_name'. Retrying in $retry_delay seconds..."
        sleep $retry_delay
        retry_count=$((retry_count + 1))
    done
    if [ -z "$podman_huser" ]; then
        error_msg "Failed to determine HUSER for user 'root' in container '$container_name' after $max_retries attempts. Is the container running and does the user exist?"
        return 1
    fi
    if [ -e "$env_file" ]; then
        # Check if file is writable, if not make it writable temporarily
        if [ ! -w "$env_file" ]; then
            if ! sudo chmod u+w "$env_file"; then
                error_msg "Failed to make $env_file writable"
                return 1
            fi
        fi
        if grep -qE '^[[:space:]]*rootless_user=' "$env_file"; then
            # Update existing key
            if ! sudo sed -i -E "s|^[[:space:]]*rootless_user=.*|rootless_user=$podman_huser|" "$env_file"; then
                error_msg "Failed to update rootless_user in $env_file"
                return 1
            fi
        else
            # Append the key
            if ! sudo sh -c "printf '\nrootless_user=%s\n' '$podman_huser' >> '$env_file'"; then
                error_msg "Failed to append rootless_user to $env_file"
                return 1
            fi
        fi
        # Restore original permissions if we changed them
        if [ ! -w "$env_file" ]; then
            if ! sudo chmod u-w "$env_file"; then
                warning_msg "Failed to restore original permissions for $env_file"
            fi
        fi
    else
        # Create new file with the key
        if ! sudo sh -c "printf 'rootless_user=%s\n' '$podman_huser' > '$env_file'"; then
            error_msg "Failed to create $env_file with rootless_user"
            return 1
        fi
    fi
    success_msg "Updated rootless_user in .env to $podman_huser"
}
# Function to remove a container
remove_container() {
    local container_name=$1
    # Check if container exists
    if ! podman inspect "$container_name" &>/dev/null; then
        error_msg "Container $container_name does not exist."
        return 1
    fi
    # Stop the container first
    stop_container "$container_name" || warning_msg "Failed to stop container $container_name"
    # Remove the container
    info_msg "Removing container $container_name..."
    if ! podman rm "$container_name"; then
        error_msg "Failed to remove container $container_name"
        return 1
    fi
    # Decompose the container
    decompose_container "$container_name" || warning_msg "Failed to decompose container $container_name"
    # Ask to remove ALL container data
    read -p "Do you want to remove ALL container data from $container_name? (y/n): " remove_container_data
    if [[ "$remove_container_data" =~ ^[Yy]$ ]]; then
        read -p "!! Are you sure you want to remove ALL container data from $container_name? !! (y/n): " remove_container_data_sure
        if [[ "$remove_container_data_sure" =~ ^[Yy]$ ]]; then
            important_msg "Removing ALL container data from $container_name..."
            if ! sudo rm -rf "$base_dir/$container_name"; then
                error_msg "Failed to remove container data from $container_name"
                return 1
            fi
            success_msg "ALL container data removed from $container_name."
        fi
    fi
    success_msg "Container $container_name removed successfully."
}
# Function to create appdata folders
create_appdata_folders() {
    local container_name=$1
    local appdata_dir="$base_dir/$container_name/appdata"
    # Check if appdata directory exists
    if [ ! -d "$appdata_dir" ]; then
        error_msg "Appdata directory $appdata_dir does not exist."
        return 1
    fi
    info_msg "Creating additional folders in appdata directory..."
    while true; do
        read -p "Enter folder name to create (or press Enter to finish): " folder_name
        if [ -z "$folder_name" ]; then
            break
        fi
        if [ -d "$appdata_dir/$folder_name" ]; then
            warning_msg "Folder $folder_name already exists."
            continue
        fi
        if ! sudo mkdir -p "$appdata_dir/$folder_name"; then
            error_msg "Failed to create folder $folder_name"
            continue
        fi
        success_msg "Created folder $folder_name in appdata directory."
        # Set proper permissions
        if ! sudo chmod 700 "$appdata_dir/$folder_name"; then
            warning_msg "Failed to set permissions for $folder_name"
        fi
        # Set ownership if rootless_user is defined
        if [ -n "$rootless_user" ]; then
            if ! podman unshare chown "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"; then
                warning_msg "Failed to set ownership for $folder_name"
            fi
        fi
    done
    success_msg "Finished creating additional folders in appdata directory."
}
# Prepares the machine for Podman
prepare_machine() {
    # Installing Podman 
    sudo apt-get update -qq && sudo apt-get install -y podman
    success_msg "Podman installed."
    # Installing Podman-compose
    sudo apt-get install -y podman-compose
    success_msg "Podman-compose installed."
    # Configuring Podman
    mkdir "/home/podman/containers"
    systemctl --user --now enable podman
    success_msg "Podman enabled."
    # Makes Podman containers run rootless
    mkdir "/home/podman/.config/containers"
    echo -e '[containers]\nrootless = true\nuserns = "nomap"' > /home/podman/.config/containers/containers.conf
    sudo usermod --add-subuids 10000-75535 podman
    sudo usermod --add-subgids 10000-75535 podman
    success_msg "Configured extra security for rootless containers (nomap)."
    # Make containers start on boot
    cp /lib/systemd/system/podman-restart.service /home/podman/.config/systemd/user/
    systemctl --user enable podman-restart.service
    loginctl enable-linger $UID
    systemctl --user --now enable podman.socket
    export DOCKER_HOST=unix:///run/user/1000/podman/podman.sock
    success_msg "Ensured Podman containers start on boot (restart: always)."
    # Add docker.io as a registry
    cp /etc/containers/registries.conf /home/podman/.config/containers/
    success_msg "Added docker.io registry."
    echo "unqualified-search-registries = [\"docker.io\"]" >> /home/podman/.config/containers/registries.conf
    # Open ports 80+ for the unpriveledged Podman containers to use
    read -p "Do you want to configure priveledged ports 80+ for the Podman containers? (y/n): " configure_priveledged_ports_yn
    if [[ "$configure_priveledged_ports_yn" =~ ^[Yy]$ ]]; then
        sudo /bin/su -c "echo -e '# Lowering privileged ports to 80 to allow us to run rootless Podman containers on lower ports\n# default: 1024\nnet.ipv4.ip_unprivileged_port_start=80' >> /etc/sysctl.d/podman-privileged-ports.conf"
        sudo sysctl --load /etc/sysctl.d/podman-privileged-ports.conf
        success_msg "Ports 80+ opened."
    fi
    # Enable better file caching for file servers
    read -p "Improve caching for file servers (Nextcloud, Jellyfin/Plex)? (y/n): " improve_caching_yn
    if [[ "$improve_caching_yn" =~ ^[Yy]$ ]]; then
        echo -e 'vm.swappiness=10\nvm.vfs_cache_pressure = 50\nfs.inotify.max_user_watches=262144' >> /etc/sysctl.conf
        success_msg "Improved file caching."
    fi
    success_msg "Machine is ready!"
    # Recommend reboot
    read -p "Reboot recommended... (y/n): " reboot_yn
    if [[ "$reboot_yn" =~ ^[Yy]$ ]]; then
        sudo reboot -f
    fi
}
# Main menu
while true; do
    header "Podman Container Management Menu"
    echo -e "${GREEN}1. List all containers${RESET}"
    echo -e "${GREEN}2. Start a container${RESET}"
    echo -e "${GREEN}3. Stop a container${RESET}"
    echo -e "${GREEN}4. Create a new container${RESET}"
    echo -e "${GREEN}5. Compose a container${RESET}"
    echo -e "${GREEN}6. Decompose a container${RESET}"
    echo -e "${GREEN}7. Browse and edit files${RESET}"
    echo -e "${GREEN}8. Add more appdata files${RESET}"
    echo -e "${GREEN}9. Reapply permissions to a container${RESET}"
    echo -e "${RED}99. Remove a container${RESET}"
    echo -e "${RED}01. Prepare machine for Podman${RESET}"
    echo -e "${BLUE}0. Exit${RESET}"
    separator
    read -p "Enter your choice (0-9, 99): " choice
    case $choice in
        1)
            list_containers
            ;;
        2)
            read -p "Enter the container name to start: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                start_container "$container_name"
            fi
            ;;
        3)
            read -p "Enter the container name to stop: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                stop_container "$container_name"
            fi
            ;;
        4)
            read -p "Enter the new container name: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                create_container "$container_name"
            fi
            ;;
        5)
            read -p "Enter the container name to compose: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                compose_container "$container_name"
            fi
            ;;
        6)
            read -p "Enter the container name to decompose: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                decompose_container "$container_name"
            fi
            ;;
        7)
            read -p "Enter the container name to browse and edit files: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                manage_files "$container_name"
            fi
            ;;
        8)
            read -p "Enter the container name to add more appdata files: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                create_appdata_folders "$container_name"
            fi
            ;;
        9)
            read -p "Enter the container name to reapply permissions: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                reapply_permissions "$container_name"
            fi
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            if [ -z "$container_name" ]; then
                error_msg "Container name cannot be empty."
            else
                remove_container "$container_name"
            fi
            ;;
        01)
            read -p "!! Are you sure you want to prep this machine for Podman !! (y/n): " prepare_machine_yn
            if [[ "$prepare_machine_yn" =~ ^[Yy]$ ]]; then
                prepare_machine
            fi
            ;;
        0)
            info_msg "Exiting..."
            exit 0
            ;;
        *)
            error_msg "Invalid choice. Please enter a number between 0 and 9, or 99."
            ;;
    esac
    read -p "Press Enter to continue..."
done
