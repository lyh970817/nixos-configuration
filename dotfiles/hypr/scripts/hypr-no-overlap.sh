#!/usr/bin/env bash


# Configuration
PADDING=20  # Minimum padding between windows
SCREEN_WIDTH=1920  # Adjust to your monitor
SCREEN_HEIGHT=1080  # Adjust to your monitor
TOP_BAR_HEIGHT=30  # Adjust if you have a bar
BOTTOM_BAR_HEIGHT=0  # Adjust if you have a bottom bar

# Calculate usable area
USABLE_Y=$TOP_BAR_HEIGHT
USABLE_HEIGHT=$((SCREEN_HEIGHT - TOP_BAR_HEIGHT - BOTTOM_BAR_HEIGHT))

get_floating_windows() {
    hyprctl clients -j | jq -r '.[] | select(.floating == true) | 
        "\(.address) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1]) \(.title)"'
}

check_overlap() {
    local x1=$1 y1=$2 w1=$3 h1=$4
    local x2=$5 y2=$6 w2=$7 h2=$8
    
    # Check if rectangles overlap
    if [ $((x1 + w1 + PADDING)) -gt $x2 ] && [ $x1 -lt $((x2 + w2 + PADDING)) ] && \
       [ $((y1 + h1 + PADDING)) -gt $y2 ] && [ $y1 -lt $((y2 + h2 + PADDING)) ]; then
        return 0  # Overlapping
    fi
    return 1  # Not overlapping
}

find_free_position() {
    local width=$1
    local height=$2
    local windows=("${@:3}")
    
    # Try different positions in a grid pattern
    local grid_x=50
    local grid_y=$USABLE_Y
    local step_x=100
    local step_y=100
    
    while [ $grid_y -lt $((USABLE_HEIGHT - height)) ]; do
        grid_x=50
        while [ $grid_x -lt $((SCREEN_WIDTH - width)) ]; do
            local overlaps=0
            
            # Check if this position overlaps with any existing window
            for window in "${windows[@]}"; do
                [ -z "$window" ] && continue
                local w_data=($window)
                local w_x=${w_data[1]}
                local w_y=${w_data[2]}
                local w_w=${w_data[3]}
                local w_h=${w_data[4]}
                
                if check_overlap $grid_x $grid_y $width $height $w_x $w_y $w_w $w_h; then
                    overlaps=1
                    break
                fi
            done
            
            if [ $overlaps -eq 0 ]; then
                echo "$grid_x $grid_y"
                return 0
            fi
            
            grid_x=$((grid_x + step_x))
        done
        grid_y=$((grid_y + step_y))
    done
    
    # Fallback: cascade position
    echo "$((50 + RANDOM % 200)) $((USABLE_Y + RANDOM % 200))"
}

rearrange_windows() {
    local mode=$1  # "cascade", "tile", "smart"
    
    echo "Rearranging floating windows (mode: $mode)..."
    
    # Get all floating windows
    mapfile -t windows < <(get_floating_windows)
    
    if [ ${#windows[@]} -eq 0 ]; then
        echo "No floating windows found"
        return
    fi
    
    case $mode in
        "cascade")
            local x=50
            local y=$USABLE_Y
            for window in "${windows[@]}"; do
                local addr=$(echo $window | cut -d' ' -f1)
                hyprctl dispatch movewindowpixel "$x $y,address:$addr"
                x=$((x + 30))
                y=$((y + 30))
            done
            ;;
            
        "tile")
            # Simple grid tiling for floating windows
            local cols=3
            local col=0
            local row=0
            local w=$((SCREEN_WIDTH / cols - PADDING * 2))
            local h=400  # Fixed height for tiling
            
            for window in "${windows[@]}"; do
                local addr=$(echo $window | cut -d' ' -f1)
                local x=$((col * (w + PADDING) + PADDING))
                local y=$((row * (h + PADDING) + USABLE_Y))
                
                hyprctl dispatch movewindowpixel "$x $y,address:$addr"
                hyprctl dispatch resizewindowpixel "$w $h,address:$addr"
                
                col=$((col + 1))
                if [ $col -ge $cols ]; then
                    col=0
                    row=$((row + 1))
                fi
            done
            ;;
            
        "smart"|*)
            # Smart placement - avoid overlaps
            local positioned_windows=()
            
            for i in "${!windows[@]}"; do
                local window="${windows[$i]}"
                local addr=$(echo $window | cut -d' ' -f1)
                local curr_x=$(echo $window | cut -d' ' -f2)
                local curr_y=$(echo $window | cut -d' ' -f3)
                local width=$(echo $window | cut -d' ' -f4)
                local height=$(echo $window | cut -d' ' -f5)
                
                # Check if current window overlaps with any positioned window
                local needs_move=0
                for prev_window in "${positioned_windows[@]}"; do
                    [ -z "$prev_window" ] && continue
                    local p_data=($prev_window)
                    if check_overlap $curr_x $curr_y $width $height \
                                   ${p_data[1]} ${p_data[2]} ${p_data[3]} ${p_data[4]}; then
                        needs_move=1
                        break
                    fi
                done
                
                if [ $needs_move -eq 1 ]; then
                    # Find new position
                    local new_pos=$(find_free_position $width $height "${positioned_windows[@]}")
                    local new_x=$(echo $new_pos | cut -d' ' -f1)
                    local new_y=$(echo $new_pos | cut -d' ' -f2)
                    
                    echo "Moving window: $addr to $new_x,$new_y"
                    hyprctl dispatch movewindowpixel "$new_x $new_y,address:$addr"
                    
                    # Update window info with new position
                    window="$addr $new_x $new_y $width $height"
                fi
                
                positioned_windows+=("$window")
            done
            ;;
    esac
}

# Main execution
case "${1:-smart}" in
    "cascade")
        rearrange_windows cascade
        ;;
    "tile")
        rearrange_windows tile
        ;;
    "smart")
        rearrange_windows smart
        ;;
    "monitor")
        # Monitor mode - continuously watch for new floating windows
        echo "Monitoring for overlapping floating windows..."
        last_count=0
        while true; do
            current_count=$(get_floating_windows | wc -l)
            if [ $current_count -ne $last_count ] && [ $current_count -gt 0 ]; then
                sleep 0.5  # Wait for window to settle
                rearrange_windows smart
                last_count=$current_count
            fi
            sleep 2
        done
        ;;
    *)
        echo "Usage: $0 [smart|cascade|tile|monitor]"
        echo "  smart   - Intelligent placement avoiding overlaps (default)"
        echo "  cascade - Cascade windows diagonally"
        echo "  tile    - Tile floating windows in a grid"
        echo "  monitor - Continuously monitor and fix overlaps"
        exit 1
        ;;
esac
