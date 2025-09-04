# Compose file option order
 - NETWORKS
    1. Socket proxy
    2. Container internal
    3. Container newt
 - VOLUMES
    1. Whatever
 - SERVICES
    1. name
    2. image
    3. restart
    4. security_opt
    5. cap_add
    6. read_only
    7. user
    8. networks
    9. ports
    10. volumes
    11. command
    12. tmpfs
    13. environment
    14. labels
    15. healthcheck
    16. depends_on
