#!/bin/sh
poem_dir="$HOME/.config/welcome-poems"
indent="                     " # 21 spaces to match fastfetch logo width

if [ -d "$poem_dir" ]; then
   poem=$(find -L "$poem_dir" -maxdepth 1 -type f 2>/dev/null | shuf -n 1)
   if [ -n "$poem" ]; then
     title=$(basename "$poem" .txt)
     formatted_title="--《$title》"
     
     # Calculate max width of the poem for right alignment
     max_width=$(wc -L < "$poem")
     title_len=${#formatted_title}
     
     # Calculate padding: ensure non-negative
     pad_len=$(( max_width - title_len ))
     if [ $pad_len -lt 0 ]; then pad_len=0; fi
     
     # Create padding string
     title_pad=$(printf "%${pad_len}s")

     echo "" # Add some separation
     # Indent every line of the poem
     sed "s/^/$indent/" "$poem"
     
     # Print the title two lines below, right aligned relative to poem
     echo ""
     echo "${indent}${title_pad}${formatted_title}"
   fi
fi
