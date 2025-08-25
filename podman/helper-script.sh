#!/bin/bash
base_dir="/home/podman/containers"

# Function to list all containers
list_containers() {
    echo "Listing all Podman containers:"
    podman ps -a
    read -p "Press Enter to continue..."
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

# Function to check container state
check_container_state() {
    local container_name=$1
    local state_info

    state_info=$(podman inspect --format "{{json .State }}" "$container_name" 2>/dev/null)

    if [ -z "$state_info" ]; then
        echo "Container $container_name does not exist."
        return 1
    fi

    echo "Container $container_name state:"
    echo "$state_info" | jq .

    # Extract status and running fields
    local status=$(echo "$state_info" | jq -r '.Status')
    local running=$(echo "$state_info" | jq -r '.Running')

    if [ "$running" = "true" ]; then
        echo "Container is running."
        return 0
    else
        echo "Container is not running. Current status: $status"
        return 1
    fi
}

# Function to run a container
start_container() {
    local container_name=$1

    if ! check_container_state "$container_name"; then
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
    else
        echo "Container $container_name is already running."
    fi

    read -p "Press Enter to continue..."
}

# Function to stop a container
stop_container() {
    local container_name=$1

    if check_container_state "$container_name"; then
        echo "Stopping container $container_name..."
        podman stop "$container_name"
        echo "Container $container_name stopped successfully."

        if [[ "$choice" == "3" ]]; then
            update_rootless_user "$container_name"
        fi
    else
        echo "Container $container_name is not running."
    fi

    read -p "Press Enter to continue..."
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

# Function to decompose a container
decompose_container() {
    local container_name=$1

    echo "Decomposing container $container_name..."

    # Update rootless_user before decomposing
    update_rootless_user "$container_name"

    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    echo "Container $container_name decomposed successfully."

    read -p "Press Enter to continue..."
}

# Function to compose a container
compose_container() {
    local container_name=$1

    echo "Composing container $container_name..."

    # Update rootless_user and permissions before composing
    update_rootless_user "$container_name"
    reapply_permissions "$container_name"

    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    echo "Container $container_name composed successfully."

    read -p "Press Enter to continue..."
}

# Function to create a new container
create_container() {
    local container_name=$1

    echo "Creating new container: $container_name"

    # Create container directories
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"

    # Create compose.yaml
    echo "Creating compose.yaml file..."
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"

    # Create .env file
    echo "Creating .env file..."
    sudo sh -c "echo -e \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > '$base_dir/$container_name/.env'"
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

    read -p "Press Enter to continue..."
}

# Function to edit files using ranger-fm
edit_files_with_ranger() {
    local container_name=$1
    local container_dir="$base_dir/$container_name"

    # Check if ranger is installed
    if ! command -v ranger &> /dev/null; then
        echo "ranger-fm is not installed. Would you like to install it now?"
        read -p "Install ranger-fm? (y/n): " install_ranger

        if [[ "$install_ranger" =~ ^[Yy]$ ]]; then
            echo "Updating system and installing ranger-fm..."
            sudo apt-get update && sudo apt-get upgrade -y
            sudo apt-get install -y ranger

            if [ $? -eq 0 ]; then
                echo "ranger-fm installed successfully."
            else
                echo "Failed to install ranger-fm. Please install it manually."
                return 1
            fi
        else
            echo "Cannot proceed without ranger-fm. Please install it manually."
            return 1
        fi
    fi

    # Create ranger config directory if it doesn't exist
    mkdir -p /home/podman/.config/ranger

    # Launch ranger in the container directory
    echo "Launching ranger-fm for container: $container_name"
    echo "You are now in the container directory: $container_dir"
    echo "Ranger navigation instructions:"
    echo "- Use arrow keys to navigate files and directories"
    echo "- Press 'Enter' to open files or enter directories"
    echo "- Press 'q' to quit ranger"
    echo "- To create a new file: press 'a' then enter filename"
    echo "- To edit a file: select it and press 'e'"
    echo "- To delete a file: select it and press 'dd'"
    echo "- To create a new directory: press 'mk' then enter directory name"

    ranger "$container_dir"

    echo "Finished editing files with ranger-fm."
    read -p "Press Enter to continue..."
}

# Apply user permissions
reapply_permissions() {
    local container_name=$1

    echo "Applying permissions for container $container_name..."

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
    local max_attempts=5
    local attempt=0
    local podman_huser=""

    echo "Updating rootless_user for container $container_name..."

    # Try to get rootless_user multiple times if container is running
    while [ $attempt -lt $max_attempts ]; do
        if check_container_state "$container_name"; then
            podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')
            if [ -n "$podman_huser" ]; then
                break
            fi
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

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

# Function to remove a container
remove_container() {
    local container_name=$1

    echo "Removing container $container_name..."

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
    read -p "Press Enter to continue..."
}

# Main menu
while true; do
    clear
    echo "========================================"
    echo "  PODMAN CONTAINER MANAGEMENT SYSTEM   "
    echo "========================================"
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
    echo "========================================"

    read -p "Enter your choice (0-99): " choice

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
            edit_files_with_ranger "$container_name"
            ;;
        8)
            read -p "Enter the container name to check state: " container_name
            check_container_state "$container_name"
            read -p "Press Enter to continue..."
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            ;;
        0)
            echo "Exiting Podman Container Management System..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 0 and 99."
            read -p "Press Enter to continue..."
            ;;
    esac
done
