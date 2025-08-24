#!/bin/bash
base_dir="/home/podman/containers"

# Function to create a new container
create_container() {
    read -p "Enter the container name: " container_name
    read -p "Enter the user ID (UID) to use: " user_id

    # Create a non-login system user with the given UID
    # -r system user, -U create group, -M no home, -s nologin shell
    if ! id -u "$username" >/dev/null 2>&1; then
      sudo useradd -r -U -u "$user_id" -M -s /usr/sbin/nologin -d "$base_dir/$container_name" "$username"
    else
      echo "User $username already exists; skipping creation."
    fi

    # Lock password to prevent password-based login
    sudo passwd -l "$username"

    # Create container directory and set ownership
    sudo mkdir -p "$base_dir/$container_name"
    sudo chown -R "$username:$username" "$base_dir/$container_name"
    
    # Create compose.yaml
    ${EDITOR:-nano} "$base_dir/$container_name/compose.yaml"
    
    # Optional .env
    read -p "Create a .env file? (y/n): " create_env
    if [ "$create_env" = "y" ]; then
      ${EDITOR:-nano} "$base_dir/$container_name/.env"
    fi

    # Apply user permissions
    chmod $user_id $base_dir/$container_name

    echo "Container $container_name created successfully with user."
}

# Function to list all containers
list_containers() {
    echo "Listing all Podman containers:"
    podman ps -a
}

# Function to remove a container
remove_container() {
    read -p "Enter the container name to remove: " container_name
    podman stop "$container_name"
    podman rm "$container_name"
    rm -rf "/home/podman/containers/$container_name"
    echo "Container $container_name removed successfully."
}

# Main menu
while true; do
    echo "Podman Container Management Menu"
    echo "1. Create a new container"
    echo "2. List all containers"
    echo "3. Remove a container"
    echo "4. Exit"
    read -p "Enter your choice (1-4): " choice

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
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a number between 1 and 4."
            ;;
    esac
done
