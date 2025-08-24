#!/bin/bash

base_dir="/home/podman/containers"
rootless_user=""

# Function to display a message with a specific color
display_message() {
    local color=$1
    local message=$2
    case $color in
        "red")
            echo -e "\033[1;31m$message\033[0m"
            ;;
        "green")
            echo -e "\033[1;32m$message\033[0m"
            ;;
        "yellow")
            echo -e "\033[1;33m$message\033[0m"
            ;;
        "blue")
            echo -e "\033[1;34m$message\033[0m"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Function to display an error message and exit
display_error() {
    local message=$1
    display_message "red" "Error: $message"
    read -p "Press Enter to continue..."
}

# Function to display a success message
display_success() {
    local message=$1
    display_message "green" "Success: $message"
    read -p "Press Enter to continue..."
}

# Function to display a warning message
display_warning() {
    local message=$1
    display_message "yellow" "Warning: $message"
    read -p "Press Enter to continue..."
}

# Function to display an info message
display_info() {
    local message=$1
    display_message "blue" "$message"
}

# Function to list all containers
list_containers() {
    display_info "Listing all Podman containers:"
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

    display_info "Waiting for container $container_name to be fully running..."

    while [ $attempt -lt $max_attempts ]; do
        status=$(podman inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
        if [ "$status" = "running" ]; then
            health_status=$(podman inspect -f '{{.State.Health.Status}}' "$container_name" 2>/dev/null)
            if [ -n "$health_status" ] && [ "$health_status" != "healthy" ]; then
                display_info "Container $container_name is running but health check is $health_status..."
            else
                display_success "Container $container_name is running and healthy."
                return 0
            fi
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            display_message "red" "Container $container_name is in $status state."
            exit_code=$(podman inspect -f '{{.State.ExitCode}}' "$container_name" 2>/dev/null)
            if [ -n "$exit_code" ] && [ "$exit_code" -ne 0 ]; then
                display_message "red" "Container exited with code $exit_code"
                display_info "Container logs:"
                podman logs "$container_name" 2>&1
            fi
            return 1
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    display_message "red" "Timeout waiting for container $container_name to start."
    display_info "Current status: $status"
    display_info "Container logs:"
    podman logs "$container_name" 2>&1
    return 1
}

# Function to start a container
start_container() {
    local container_name=$1

    reapply_permissions "$container_name"
    display_info "Starting container $container_name..."
    podman start "$container_name"

    if ! wait_for_container_running "$container_name"; then
        display_message "red" "Error: Container $container_name did not start properly."
        display_info "Container logs:"
        podman logs "$container_name" 2>&1
        display_info "Attempting to restart container $container_name..."
        podman restart "$container_name"

        if ! wait_for_container_running "$container_name"; then
            display_error "Container $container_name failed to start after restart."
            return 1
        fi
    fi

    update_rootless_user "$container_name"
    display_success "Container $container_name started successfully."
}

# Function to stop a container
stop_container() {
    local container_name=$1

    if [[ "$choice" == "3" ]]; then
        update_rootless_user "$container_name"
    fi

    podman stop "$container_name"
    display_success "Container $container_name stopped successfully."
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

        sudo mkdir -p "$appdata_dir/$folder_name"
        display_success "Created folder: $appdata_dir/$folder_name"
        sudo chmod 700 "$appdata_dir/$folder_name"

        if [ -n "$rootless_user" ]; then
            podman unshare chown "$rootless_user:$rootless_user" "$appdata_dir/$folder_name"
        fi
    done
}

# Function to decompose a container
decompose_container() {
    local container_name=$1

    display_info "Decomposing container $container_name..."
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    display_success "Container $container_name decomposed successfully."
}

# Function to compose a container
compose_container() {
    local container_name=$1

    display_info "Composing container $container_name..."
    update_rootless_user "$container_name"
    reapply_permissions "$container_name"
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    display_success "Container $container_name composed successfully."
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
    display_success "Container $container_name created successfully."

    read -p "Do you want to compose the container now? (y/n): " compose_now
    if [[ "$compose_now" =~ ^[Yy]$ ]]; then
        compose_container "$container_name"
    fi
}

# Function to apply user permissions
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

    display_success "Permissions applied successfully."
}

# Function to load rootless_user from .env
load_rootless_user() {
    local container_name=$1
    local env_file="$base_dir/$container_name/.env"

    if [[ ! -r "$env_file" ]]; then
        display_error "Cannot read $env_file"
        return 1
    fi

    local line
    line=$(sudo grep -m1 -E '^[[:space:]]*rootless_user[[:space:]]*=' "$env_file") || {
        display_error "rootless_user not found in $env_file"
        return 1
    }

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

    local podman_huser
    podman_huser=$(podman top "$container_name" user huser 2>/dev/null | awk 'NR>1 && $1=="abc" {print $2; exit}')

    if [ -z "$podman_huser" ]; then
        display_error "Could not determine HUSER for user 'abc' in container '$container_name'. Is it running and does user exist?"
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

    display_success "Updated rootless_user in .env"
}

# Function to remove a container
remove_container() {
    local container_name=$1

    stop_container "$container_name"
    podman rm "$container_name"
    decompose_container "$container_name"

    read -p "Do you want to remove ALL container data from $container_name? (y/n): " remove_container_data
    if [[ "$remove_container_data" =~ ^[Yy]$ ]]; then
        read -p "!! Are you sure you want to remove ALL container data from $container_name? !! (y/n): " remove_container_data_sure
        if [[ "$remove_container_data_sure" =~ ^[Yy]$ ]]; then
            sudo rm -rf "$base_dir/$container_name"
            display_success "ALL container data removed from $container_name."
        fi
    fi

    display_success "Container $container_name removed successfully."
}

# Function to edit files using ranger
edit_files_with_ranger() {
    local container_name=$1
    local container_dir="$base_dir/$container_name"

    if ! command -v ranger &> /dev/null; then
        display_warning "Ranger is not installed. Installing now..."
        sudo apt-get update
        sudo apt-get upgrade -y
        sudo apt-get install -y ranger
    fi

    display_info "Opening $container_dir in ranger. Use the following commands:"
    display_info "  - h/l: Move left/right (change directory)"
    display_info "  - j/k: Move down/up (select file)"
    display_info "  - gg/G: Go to top/bottom of the list"
    display_info "  - i: Preview file"
    display_info "  - d: Create a new directory"
    display_info "  - n: Create a new file"
    display_info "  - dd: Delete file or directory"
    display_info "  - cw: Rename file or directory"
    display_info "  - q: Quit ranger"

    ranger "$container_dir"
    display_success "Finished editing files in $container_dir."
}

# Main menu
while true; do
    clear
    echo "Podman Container Management Menu"
    echo "1. List all containers"
    echo "2. Start a container"
    echo "3. Stop a container"
    echo "4. Create a new container"
    echo "5. Compose a container"
    echo "6. Decompose a container"
    echo "7. Edit container files"
    echo "8. Exit"
    echo "99. Remove a container"

    read -p "Enter your choice (1-8, 99): " choice

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
            display_info "Exiting..."
            exit 0
            ;;
        99)
            read -p "Enter the container name to remove: " container_name
            remove_container "$container_name"
            ;;
        *)
            display_error "Invalid choice. Please enter a number between 1 and 8, or 99."
            ;;
    esac
done
