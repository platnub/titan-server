#!/bin/bash
base_dir="/home/podman/containers"

# Function to create a new container
create_container() {
    read -p "Enter the container name: " container_name
#    read -p "Enter the user ID (UID) to use: " user_id

    # Create a non-login system user with the given UID
    # -r system user, -U create group, -M no home, -s nologin shell
#    if ! id -u "$container_name" >/dev/null 2>&1; then
#      useradd -r -U -u "$user_id" -M -s /usr/sbin/nologin -d "$base_dir/$container_name" "$container_name"
#    else
#      echo "User $container_name already exists; skipping creation."
#    fi

    # Lock password to prevent password-based login
#    passwd -l "$container_name"

    # Create container directories
    sudo mkdir -p "$base_dir/$container_name"
    sudo mkdir -p "$base_dir/$container_name/appdata"
    sudo mkdir -p "$base_dir/$container_name/logs"
    sudo mkdir -p "$base_dir/$container_name/secrets"
    
    # Create compose.yaml
    sudo ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"
    
    # Optional .env
    sudo /bin/su -c "echo -e \"PUID=1000\nPGID=1000\nTZ=\"Europe/Amsterdam\"\nDOCKERDIR=\"$base_dir\"\nDATADIR=\"$base_dir/$container_name/appdata\"\" > $base_dir/$container_name/.env"
    sudo ${EDITOR:-nano} "$base_dir/$container_name/.env"

    # Apply user permissions
    sudo chmod 700 "$base_dir/$container_name"
    sudo chmod 700 "$base_dir/$container_name/appdata"
    sudo chmod 700 "$base_dir/$container_name/logs"
    sudo chmod 400 "$base_dir/$container_name/secrets"
    sudo chmod 400 "$base_dir/$container_name/compose.yaml"
    sudo chmod 400 "$base_dir/$container_name/.env"
    chown -R podman:podman "$base_dir/$container_name"
    podman unshare chown -R 1000:1000 "$base_dir/$container_name"
    
    echo "Container $container_name created successfully with user."

    # Ask to run the container
    read -p "Do you want to run the container now? (y/n): " run_now
    if [[ "$run_now" =~ ^[Yy]$ ]]; then
        run_container "$container_name"
    fi
}
# Function to run a container
run_container() {
    local container_name=$1
    podman-compose --file "$base_dir/$container_name/compose.yaml" up --detach
    echo "Container $container_name started successfully."
}

# Function to stop a container
stop_container() {
    read -p "Enter the container name to stop: " container_name
    podman-compose --file "$base_dir/$container_name/compose.yaml" down
    echo "Container $container_name stopped successfully."
}

# Function to list all containers
list_containers() {
    echo "Listing all Podman containers:"
    podman ps -a
}

# Function to remove a container
remove_container() {
    read -p "Enter the container name to remove: " container_name
#    stop_container $container_name
    podman rm "$container_name"
    sudo rm -rf "$base_dir/$container_name"
    echo "Container $container_name removed successfully."
}

# Main menu
while true; do
    echo "Podman Container Management Menu"
    echo "1. Create a new container"
    echo "2. List all containers"
    echo "3. Remove a container"
    echo "4. Run a container"
    echo "5. Stop a container"
    echo "6. Exit"
    read -p "Enter your choice (1-6): " choice

    case $choice in
        1)
            create_container
            ;;
        2)
            list_containers
            ;;
        3)
            remove_container
            ;;
        4)
            read -p "Enter the container name to run: " container_name
            run_container "$container_name"
            ;;
        5)
            stop_container
            ;;
        6)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 6."
            ;;
    esac
done
