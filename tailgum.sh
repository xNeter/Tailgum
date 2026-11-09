#!/usr/bin/env bash

# ==============================================================================
# tailgum - Interactive Tailscale & Exit Node Manager
# Built with Bash, Gum (Charmbracelet), and JQ
# ==============================================================================

# 1. Dependency validation
check_dependencies() {
    local missing_deps=()
    for cmd in tailscale gum jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "❌ Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install the missing package(s) using your distribution's package manager before running this script." >&2
        exit 1
    fi
}

check_dependencies

# 2. Check for root privileges (Auto-elevation)
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

# 3. Verify that the tailscaled daemon is active on startup
if ! systemctl is-active --quiet tailscaled; then
    gum style --foreground 214 "⚠️  The tailscaled service is currently stopped."
    
    gum spin --spinner dot --title "Starting tailscaled service..." -- \
        systemctl start tailscaled
    
    gum spin --spinner pulse --title "Bringing Tailscale network up (tailscale up)..." -- \
        bash -c "tailscale up && sleep 1.5"
fi

# 4. Function to fetch and parse Tailscale status via JSON
refresh_data() {
    local status_json
    status_json=$(tailscale status --json 2>/dev/null)

    if [[ -z "$status_json" ]]; then
        gum style --foreground 196 "❌ Error: Unable to retrieve Tailscale status."
        exit 1
    fi

    # a) General backend state (e.g., Running, Stopped, NeedsLogin)
    TS_STATE=$(echo "$status_json" | jq -r '.BackendState // "Unknown"')

    # b) Connected devices (Self + Peers where Online == true)
    TS_ONLINE_PEERS=$(echo "$status_json" | jq -r '
        [ .Self, (.Peer // {} | .[]) ]
        | map(select(.Online == true))
        | map("• \(.HostName) (\(.TailscaleIPs[0] // "No IP"))")
        | join("\n")
    ')

    # c) Available Exit Nodes (Separated by Online / Offline state)
    TS_EXIT_NODES_ONLINE=$(echo "$status_json" | jq -r '
        [ (.Peer // {} | .[]) | select(.ExitNodeOption == true and .Online == true) ]
        | map("🟢 \(.HostName) (\(.TailscaleIPs[0] // "No IP"))")
        | join("\n")
    ')

    TS_EXIT_NODES_OFFLINE=$(echo "$status_json" | jq -r '
        [ (.Peer // {} | .[]) | select(.ExitNodeOption == true and .Online == false) ]
        | map("🔴 \(.HostName) (\(.TailscaleIPs[0] // "No IP"))")
        | join("\n")
    ')

    # d) Currently active Exit Node (Clean .HostName checking ExitNode and ExitNodeStatus)
    TS_CURRENT_EXIT_NODE=$(echo "$status_json" | jq -r '
        (.ExitNodeStatus.ID // "") as $exit_id |
        (.ExitNodeStatus.Online // false) as $exit_online |
        [ (.Peer // {} | .[]) | select(.ExitNode == true or (.ExitNodeStatus.Online? == true) or ($exit_online == true and .ID == $exit_id)) ]
        | if length > 0 then .[0].HostName else "None" end
    ')
}

# 5. UI and Action Functions
show_header() {
    clear
    gum style \
        --foreground 212 --border-foreground 212 --border double \
        --align center --width 50 --margin "1 0" --padding "1 2" \
        "Tailscale Manager"
}

pause_prompt() {
    echo ""
    gum style --foreground 240 "Press any key to return to the menu..."
    read -rsn1
}

connect_exit_node() {
    # Display notice of offline/unavailable Exit Nodes at the top
    if [[ -n "$TS_EXIT_NODES_OFFLINE" ]]; then
        gum style --border rounded --padding "0 2" --border-foreground 196 --margin "0 0 1 0" \
            "$(gum style --bold --foreground 196 "⚠️  OFFLINE Exit Nodes (Unavailable for selection):")" \
            "$TS_EXIT_NODES_OFFLINE"
    else
        gum style --foreground 240 --margin "0 0 1 0" "ℹ️  All configured Exit Nodes are currently online."
    fi

    # Ensure there is at least one online Exit Node available to select
    if [[ -z "$TS_EXIT_NODES_ONLINE" ]]; then
        gum style --foreground 214 "❌ No online Exit Nodes are available at this moment."
        return 0
    fi

    # Convert online nodes into a Bash array for gum choose
    local nodes_array=()
    mapfile -t nodes_array <<< "$TS_EXIT_NODES_ONLINE"

    local selection
    selection=$(gum choose \
        --cursor.foreground="212" \
        --header="Select an Exit Node to connect:" \
        --header.foreground="39" \
        "${nodes_array[@]}" \
        "↩️  Back")

    # Return immediately to main menu if user selects Back or presses Esc/Ctrl+C
    if [[ "$selection" == "↩️  Back" || -z "$selection" ]]; then
        return 1
    fi

    # Dynamically extract node name and IP from selection (Format: "🟢 hostname (IP)")
    local node_name selected_node_ip
    node_name=$(echo "$selection" | awk '{print $2}')
    selected_node_ip=$(echo "$selection" | awk -F'[()]' '{print $2}')

    echo ""
    # Execute connection command with a 1.5s delay to allow tailscaled to update its state
    if gum spin --spinner minidot --title "Connecting to $node_name ($selected_node_ip)..." -- \
        bash -c "tailscale set --exit-node='$selected_node_ip' --exit-node-allow-lan-access=true && sleep 1.5"; then
        
        gum style --border rounded --padding "1 2" --border-foreground 42 \
            "$(gum style --bold --foreground 42 "✅ Connected successfully!")" \
            "• Active Exit Node: $(gum style --bold "$node_name")" \
            "• Local LAN Access: $(gum style --foreground 42 "Allowed (true)")"
    else
        gum style --border rounded --padding "1 2" --border-foreground 196 \
            "$(gum style --bold --foreground 196 "❌ Connection failed")" \
            "Could not set Exit Node to $node_name ($selected_node_ip)."
    fi

    return 0
}

# ==============================================================================
# Main Execution Loop
# ==============================================================================

gum spin --spinner minidot --title "Loading Tailscale status..." -- sleep 0.2
refresh_data

while true; do
    show_header

    SELECTED_OPTION=$(gum choose \
        --cursor.foreground="212" \
        --header="Select an action:" \
        --header.foreground="39" \
        "View active exit nodes" \
        "Connect to exit node" \
        "Disable exit node traffic" \
        "Disable Tailscale" \
        "View connection status" \
        "Refresh data / Status" \
        "Exit")

    echo ""

    case "$SELECTED_OPTION" in
        "View active exit nodes")
            gum style --border rounded --padding "1 2" --border-foreground 214 \
                "$(gum style --bold --foreground 214 "📡 Available Exit Nodes (Online):")" \
                "${TS_EXIT_NODES_ONLINE:-  No active exit nodes at this moment.}" \
                "" \
                "$(gum style --italic --foreground 245 "Offline / Down:")" \
                "${TS_EXIT_NODES_OFFLINE:-  None}"
            ;;

        "Connect to exit node")
            # If connect_exit_node returns 1 (user selected "Back"), skip pause
            if ! connect_exit_node; then
                continue
            fi
            ;;

        "Disable exit node traffic")
            if [[ "$TS_CURRENT_EXIT_NODE" == "None" ]]; then
                gum style --foreground 214 "ℹ️  You are not currently routing traffic through any Exit Node."
            else
                gum spin --spinner minidot --title "Disabling exit node traffic..." -- \
                    bash -c "tailscale set --exit-node= && sleep 1.5"
                gum style --foreground 42 "✅ Exit node traffic disabled. Direct tailnet connection remains active."
            fi
            ;;

        "Disable Tailscale")
            if [[ "$TS_STATE" == "Stopped" ]]; then
                gum style --foreground 214 "ℹ️  Tailscale is already stopped."
            else
                gum spin --spinner pulse --title "Disconnecting Tailscale (tailscale down)..." -- \
                    bash -c "tailscale down && sleep 1.5"
                gum style --foreground 42 "🛑 Tailscale has been disconnected."
            fi
            ;;

        "View connection status")
            if [[ "$TS_STATE" == "Running" ]]; then
                READABLE_STATE="$(gum style --foreground 42 --bold "Connected (Running)")"
            else
                READABLE_STATE="$(gum style --foreground 196 --bold "Disconnected ($TS_STATE)")"
            fi

            gum style --border rounded --padding "1 2" --border-foreground 39 \
                "$(gum style --bold --foreground 39 "📊 Connection Summary")" \
                "" \
                "• Tailscale Status: $READABLE_STATE" \
                "• Current Exit Node: $(gum style --bold --foreground 212 "$TS_CURRENT_EXIT_NODE")"
            ;;

        "Refresh data / Status")
            gum spin --spinner minidot --title "Syncing with Tailscale..." -- sleep 1
            refresh_data
            continue
            ;;

        "Exit"|"")
            gum style --foreground 212 "👋 Goodbye!"
            exit 0
            ;;
    esac

    # Refresh state variables after executing the chosen action and wait for keypress
    refresh_data
    pause_prompt
done
