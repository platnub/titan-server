#!/bin/bash
base_dir="/home/podman/containers"

# Function to list all containers
list_containers() {
    echo "Listing all Podman containers:"
    podman ps -a
}

# Function to wait for container to be fully running
wait_for_container_running() {
    local container_name=$1
    local max_attempts=60  # Increased timeout
    local attempt=0
    local status
    local health_status
    echo "Waiting for container $container_name to be fully running..."
    while [ $attempt -lt $max_attempts ]; do
        # Get container status
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
        if [ "$status" = "running" ]; then
            # Check if the container has a health check
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ -n "$health_status" ] && [ "$health_status" != "healthy" ]; then
                # If there's a health check but it's not healthy yet
                echo "Container $container_name is running but health check is $health_status..."
            else
                # Either no health check or it's healthy
                echo "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            echo "Container $container_name is in $status state."
            # Get exit code for more detailed error
            exit_code=$(podman inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null)
            if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
                echo "Container exited with code $exit_code"
                echo "Container logs:"
                podman logs "$container_name" 2>&1
            fi
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    echo "Timeout waiting for container $container_name to start."
    echo "Current status: $status"
    echo "Container logs:"
    podman logs "$container_name" 2>&1
    return 1
}

# Function to run a container
start_container() {
    local container_name=$1
    reapply_permissions "$container_name"
    # Start the container
    echo "Starting container $container_name..."
    podman start "$container_name"
    # Wait for the container to be fully running
    if ! wait_for_container_running "$container_name"; then
        echo "Error: Container $container_name did not start properly."
        # Check container logs for errors
        echo "Container logs:"
        podman logs "$container_name" 2>&1
        # Try to restart the container if it failed
        echo "Attempting to restart container $container_name..."
        podman restart "$container_name"
        # Wait again
        if ! wait_for_container_running "$container_name"; then
            echo "Error: Container $container_name failed to start after restart."
            return 1
        fi
    fi
    update_rootless_user "$container_name"
    echo "Container $container_name started successfully."
}

# Function to stop a container
stop_container() {
    local container_name=$1
    # Only update .env if this was called from option 3 in the menu
    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi
    podman stop "$container_name"
    echo "Container $container_name stopped successfully."
}

# Function to manage files (browse, edit, create, delete)
manage_files() {
    local container_name=$1
    local container_dir="$base_dir/$container_name"
    local current_dir="$container_dir"

    # Check if nano is installed
    if ! command -v nano &> /dev/null; then
        echo "nano is not installed. Please install it first."
        read -p "Do you want to install nano now? (y/n): " install_nano
        if [[ "$install_nano" =~ ^[Yy]$ ]]; then
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y nano
            echo "nano installed successfully."
        else
            echo "Cannot proceed without nano. Exiting..."
            return 1
        fi
    fi

    while true; do
        clear
        echo "============================================="
        echo "Current Directory: $current_dir"
        echo "============================================="
        echo "Files and Directories:"
        echo "============================================="

        # List files and directories with proper sudo for appdata
        if [[ "$current_dir" == *"appdata"* ]]; then
            local items=($(sudo ls -pA "$current_dir" 2>/dev/null))
        else
            local items=($(ls -pA "$current_dir" 2>/dev/null))
        fi

        for i in "${!items[@]}"; do
            echo "$((i + 1)). ${items[$i]}"
        done

        echo "============================================="
        echo "Options:"
        echo "============================================="
        echo "0. Go back to previous directory"
        echo "c. Create new file"
        echo "d. Delete file/directory"
        echo "99. Exit file manager"
        echo "============================================="
        read -p "Enter your choice (1-${#items[@]}, 0, c, d, or 99): " choice

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -eq 0 ]; then
                if [ "$current_dir" != "$container_dir" ]; then
                    current_dir=$(dirname "$current_dir")
                else
                    echo "Already at the root directory of the container."
                    sleep 2
                fi
            elif [ "$choice" -eq 99 ]; then
                break
            elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
                local selected_item="${items[$((choice - 1))]}"
                if [ -d "$current_dir/$selected_item" ]; then
                    if [[ "$current_dir/$selected_item" == *"appdata"* ]]; then
                        echo "WARNING: You are entering the appdata directory."
                        echo "This directory contains sensitive permissions. Be careful with your changes."
                        echo "This operation requires sudo rights."
                        read -p "Press Enter to continue or Ctrl+C to cancel..."
                    fi
                    current_dir="${current_dir%/}/${selected_item%/}"
                else
                    echo "Opening $current_dir/$selected_item with nano..."
                    if [[ "$current_dir" == *"appdata"* ]]; then
                        echo "WARNING: You are editing files in the appdata directory."
                        echo "This directory contains sensitive permissions. Be careful with your changes."
                        read -p "Press Enter to continue or Ctrl+C to cancel..."
                        sudo nano "$current_dir/$selected_item"
                    else
                        nano "$current_dir/$selected_item"
                    fi
                fi
            else
                echo "Invalid choice. Please enter a valid number."
                sleep 2
            fi
        elif [[ "$choice" == "c" ]]; then
            read -p "Enter new file name: " new_file
            if [[ -n "$new_file" ]]; then
                if [[ "$current_dir" == *"appdata"* ]]; then
                    echo "WARNING: You are creating a file in the appdata directory."
                    echo "This directory contains sensitive permissions. Be careful with your changes."
                    read -p "Press Enter to continue or Ctrl+C to cancel..."
                    sudo touch "$current_dir/$new_file"
                    sudo chmod 600 "$current_dir/$new_file"
                    if [ -n "$rootless_user" ]; then
                        podman unshare chown "$rootless_user:$rootless_user" "$current_dir/$new_file"
                    fi
                else
                    touch "$current_dir/$new_file"
                fi
                echo "File $current_dir/$new_file created."
                sleep 2
            fi
        elif [[ "$choice" == "d" ]]; then
            read -p "Enter file/directory name to delete: " delete_item
            if [[ -n "$delete_item" ]]; then
                if [[ "$current_dir" == *"appdata"* ]]; then
                    echo "WARNING: You are deleting a file/directory in the appdata directory."
                    echo "This directory contains sensitive permissions. Be careful with your changes."
                    read -p "Press Enter to continue or Ctrl+C to cancel..."
                    sudo rm -rf "$current_dir/$delete_item"
                else
                    rm -rf "$current_dir/$delete_item"
                fi
                echo "Deleted $current_dir/$delete_item"
                sleep 2
            fi
        else
            echo "Invalid input. Please enter a number, 'c', 'd', or '99'."
            sleep 2
        fi
    done
}

# Function to create new folders in appdata
create_appdata_folders() {
    local container_name=$1
    local appdata_dir="$base_dir/$container_name/appdata"
    echo "Checking for new folders to create in $appdata_dir..."
    while true; do
        read -p "Enter a folder name to create in appdata (leave empty to finish): " folder_name
        if [[ -z "$folder_name" ]]; then
            break
        fi
        # Create the folder
        sudo mkdir -p "$appdata_dir/$folder_name"
        echo "Created folder: $appdata_dir/$folder_name"
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
    update_rootless_user "$container_name"
    echo "Decomposing container $container_name..."
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    echo "Container $container_name decomposed successfully."
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    echo "Composing container $container_name..."
    reapply_permissions "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    # Wait for container to be running
    if ! wait_for_container_running "$container_name"; then
        echo "Error: Container $container_name did not start properly after composition."
        return 1
    fi
    update_rootless_user "$container_name"
    echo "Container $container_name composed successfully."
}

# Function to create a new container
create_container() {
    local container_name=$1
    # Create container directories
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"
    # Create compose.yaml
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"
    # Create .env file
    sudo sh -c "echo \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"
    # Ask to create new folders in appdata
    read -p "Do you want to create any new folders in the appdata directory? (y/n): " create_folders
    if [[ "$create_folders" =~ ^[Yy]$ ]]; then
        create_appdata_folders "$container_name"
    fi
    reapply_permissions "$container_name"
    echo "Container $container_name created successfully."
    # Ask to run the container
    read -p "Do you want to compose the container now? (y/n): " compose_now
    if [[ "$compose_now" =~ ^[Yy]$ ]]; then
        compose_container "$container_name"
    fi
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1
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
    echo "Permissions applied successfully."
}

# Load rootless_user from .env
load_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    if [[ ! -r "$env_file" ]]; then
        echo "Cannot read $env_file" >&2
        return 1
    fi
    # Get the line rootless_user=...
    local line
    line=$(sudo grep -m1 -E '^[[:space:]]*rootless_user[[:space:]]*=' "$env_file") || {
        echo "rootless_user not found in $env_file" >&2
        return 1
    }
    # Extract value, strip inline comments/whitespace and surrounding quotes
    local val=${line#*=}
    val=${val%%#*}
    val=$(printf '%s\n' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    val=$(printf '%s\n' "$val" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")
    if [[ -z "$val" ]]; then
        echo "rootless_user value is empty in $env_file" >&2
        return 1
    fi
    rootless_user="$val"
    export rootless_user
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
        echo "Error: Container $container_name is not running. Cannot update rootless_user."
        return 1
    fi
    while [ $retry_count -lt $max_retries ]; do
        # Get HUSER for user "abc"
        podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')
        if [ -n "$podman_huser" ]; then
            break
        fi
        echo "Attempt $((retry_count + 1)): Could not determine HUSER for user 'abc' in container '$container_name'. Retrying in $retry_delay seconds..."
        sleep $retry_delay
        retry_count=$((retry_count + 1))
    done
    if [ -z "$podman_huser" ]; then
        echo "Failed to determine HUSER for user 'abc' in container '$container_name' after $max_retries attempts. Is the container running and does the user exist?"
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
    echo "Updated rootless_user in .env"
}

# Function to remove a container
remove_container() {
    local container_name=$1
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
            echo "ALL container data removed from $container_name."
        fi
    fi
    echo "Container $container_name removed successfully."
}

# Main menu
while true; do
    echo "============================================="
    echo "Podman Container Management Menu"
    echo "============================================="
    echo "1. List all containers"
    echo "2. Start a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "5. Compose a container"
    echo "6. Decompose a container"
    echo "7. Browse and edit files"
    echo "8. Add more appdata files"
    echo "9. Reapply permissions to a container"
    echo "99. Remove a container"
    echo "0. Exit"
    echo "============================================="
    read -p "Enter your choice (0-9, 99): " choice
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
            read -p "Enter the container name to browse and edit files: " container_name
            manage_files "$container_name"
            ;;
        8)
            read -p "Enter the container name to add more appdata files: " container_name
            create_appdata_folders "$container_name"
            ;;
        9)
            read -p "Enter the container name to reapply permissions: " container_name
            reapply_permissions "$container_name"
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 0 and 9, or 99."
            ;;
    esac
    read -p "Press Enter to continue..."
done
