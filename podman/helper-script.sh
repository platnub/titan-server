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
            # Use podman unshare to change ownership inside the container's user namespace
            # Only apply to contents of appdata directory
            if [ -d "$container_dir/appdata" ]; then
                # First find all items in appdata with sudo
                while IFS= read -r -d '' item; do
                    # Skip if the item is a mount point from the container
                    if ! podman inspect "$container_name" | grep -q "$item"; then
                        # Then apply rootless_user ownership with podman unshare
                        podman unshare chown -R "$rootless_user:$rootless_user" "$item" 2>/dev/null || true
                    fi
                done < <(sudo find "$container_dir/appdata" -mindepth 1 -print0)
            fi
        fi
    fi

    display_success "Permissions applied successfully."
}
