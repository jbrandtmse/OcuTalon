printf '%s\nwrite "DONE",!\nhalt\n' "$2" | docker exec -i "$1" iris session iris -U REPRO 2>&1 | tr -d '\r'
