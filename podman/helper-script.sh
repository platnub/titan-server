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
    local max_attempts=60
    local attempt=0
    local status
    local health_status
    echo "Waiting for container $container_name to be fully running..."
    while [ $attempt -lt $max_attempts ]; do
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
        if [ "$status" = "running" ]; then
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ -n "$health_status" ] && [ "$health_status" != "healthy" ]; then
                echo "Container $container_name is running but health check is $health_status..."
            else
                echo "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            echo "Container $container_name is in $status state."
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
    echo "Starting container $container_name..."
    podman start "$container_name"
    if ! wait_for_container_running "$container_name"; then
        echo "Error: Container $container_name did not start properly."
        echo "Container logs:"
        podman logs "$container_name" 2>&1
        echo "Attempting to restart container $container_name..."
        podman restart "$container_name"
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
    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi
    podman stop "$container_name"
    echo "Container $container_name stopped successfully."
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
        sudo mkdir -p "$appdata_dir/$folder_name"
        echo "Created folder: $appdata_dir/$folder_name"
        sudo chmod 700 "$appdata_dir/$folder_name"
        if [ -n "$rootless_user" ]; then
            podman unshare chown "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"
        fi
    done
}

# Function to decompose a container (stop and remove containers)
decompose_container() {
    local container_name=$1
    echo "Decomposing container $container_name..."
    update_rootless_user "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    echo "Container $container_name decomposed successfully."
}

# Function to compose a container (start containers)
compose_container() {
    local container_name=$1
    echo "Composing container $container_name..."
    reapply_permissions "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    echo "Container $container_name composed successfully."
}

# Function to edit files using ranger-fm
edit_files_with_ranger() {
    local container_name=$1
    local container_dir="$base_dir/$container_name"

    # Check if ranger is installed
    if ! command -v ranger &> /dev/null; then
        echo "ranger-fm is not installed. Would you like to install it? (y/n)"
        read -p "Enter your choice: " install_ranger
        if [[ "$install_ranger" =~ ^[Yy]$ ]]; then
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y ranger
            echo "ranger-fm has been installed successfully."
        else
            echo "Cannot proceed without ranger-fm. Exiting..."
            return 1
        fi
    fi

    # Create config directory if it doesn't exist
    mkdir -p /home/podman/.config/ranger

    # Launch ranger with the container directory
    echo "Launching ranger-fm for container $container_name..."
    echo "You can navigate using the following commands:"
    echo "- Arrow keys: Move cursor"
    echo "- Enter: Open file/directory"
    echo "- Backspace: Go up one directory"
    echo "- h: Show hidden files"
    echo "- : (colon): Enter command mode"
    echo "- q: Quit ranger"
    echo "- cw: Create new file"
    echo "- dd: Delete file/directory"
    echo "- yy: Copy file/directory"
    echo "- pp: Paste file/directory"

    ranger "$container_dir"

    echo "File editing session completed for container $container_name."
}

# Function to check container state
check_container_state() {
    local container_name=$1
    echo "Checking state of container $container_name..."
    state_info=$(podman inspect --format "{{json .State }}" "$container_name" 2>/dev/null)
    if [ -z "$state_info" ]; then
        echo "Container $container_name does not exist."
        return 1
    fi

    echo "Container state information:"
    echo "$state_info" | jq .

    status=$(echo "$state_info" | jq -r '.Status')
    running=$(echo "$state_info" | jq -r '.Running')

    echo "Container status: $status"
    echo "Container running: $running"

    if [ "$running" = "true" ]; then
        update_rootless_user "$container_name"
    fi
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1
    sudo chmod 700 "$base_dir/$container_name"
    sudo chmod 700 "$base_dir/$container_name/appdata"
    sudo chmod 700 "$base_dir/$container_name/logs"
    sudo chmod 400 "$base_dir/$container_name/secrets"
    sudo chmod 400 "$base_dir/$container_name/compose.yaml"
    sudo chmod 400 "$base_dir/$container_name/.env"
    sudo chown -R podman:podman "$base_dir/$container_name"
    if [ -f "$base_dir/$container_name/.env" ]; then
        load_rootless_user "$container_name"
        if [ -n "$rootless_user" ]; then
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
    local line
    line=$(sudo grep -m1 -E '^[[:space:]]*rootless_user[[:space:]]*=' "$env_file") || {
        echo "rootless_user not found in $env_file" >&2
        return 1
    }
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

# Function to update rootless_user in .env
update_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"
    local podman_huser
    podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')
    if [ -z "$podman_huser" ]; then
        echo "Could not determine HUSER for user 'abc' in container '$container_name'. Is it running and does user exist?"
        return 1
    fi
    if [ -e "$env_file" ]; then
        if [ ! -w "$env_file" ]; then
            sudo chmod u+w "$env_file"
        fi
        if grep -qE '^[[:space:]]*rootless_user=' "$env_file"; then
            sudo sed -i -E "s|^[[:space:]]*rootless_user=.*|rootless_user=$podman_huser|" "$env_file"
        else
            sudo sh -c "printf '\nrootless_user=%s\n' '$podman_huser' >> '$env_file'"
        fi
        if [ ! -w "$env_file" ]; then
            sudo chmod u-w "$env_file"
        fi
    else
        sudo sh -c "printf 'rootless_user=%s\n' '$podman_huser' > '$env_file'"
    fi
    echo "Updated rootless_user in .env"
}

# Function to create a new container
create_container() {
    local container_name=$1
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"
    sudo sh -c "echo -e \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"
    read -p "Do you want to create any new folders in the appdata directory? (y/n): " create_folders
    if [[ "$create_folders" =~ ^[Yy]$ ]]; then
        create_appdata_folders "$container_name"
    fi
    reapply_permissions "$container_name"
    echo "Container $container_name created successfully."
    read -p "Do you want to compose the container now? (y/n): " compose_now
    if [[ "$compose_now" =~ ^[Yy]$ ]]; then
        compose_container "$container_name"
    fi
}

# Function to remove a container
remove_container() {
    local container_name=$1
    stop_container "$container_name"
    podman rm "$container_name"
    decompose_container "$container_name"
    read -p "Do you want to remove ALL container data from $container_name? (y/n): " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        read -p "!! Are you sure you want to remove ALL container data from $container_name? !! (y/n): " confirm_remove
        if [[ "$confirm_remove" =~ ^[Yy]$ ]]; then
            sudo rm -rf "$base_dir/$container_name"
            echo "ALL container data removed from $container_name."
        fi
    fi
    echo "Container $container_name removed successfully."
}

# Main menu
while true; do
    clear
    echo "============================================"
    echo "  PODMAN CONTAINER MANAGEMENT SYSTEM"
    echo "============================================"
    echo "1. List all containers"
    echo "2. Start a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "5. Compose a container"
    echo "6. Decompose a container"
    echo "7. Edit container files with ranger-fm"
    echo "8. Check container state"
    echo "99. Remove a container"
    echo "0. Exit"
    echo "============================================"
    read -p "Enter your choice (0-99): " choice

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
            read -p "Enter the container name to decompose: " container_name
            decompose_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        7)
            read -p "Enter the container name to edit files: " container_name
            edit_files_with_ranger "$container_name"
            read -p "Press Enter to continue..."
            ;;
        8)
            read -p "Enter the container name to check state: " container_name
            check_container_state "$container_name"
            read -p "Press Enter to continue..."
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            read -p "Press Enter to continue..."
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 0 and 99."
            read -p "Press Enter to continue..."
            ;;
    esac
done
