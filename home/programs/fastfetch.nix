{ config, pkgs, ... }:

let
  fastfetchAudio = pkgs.writeShellApplication {
    name = "fastfetch-audio";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      gnused
      wireplumber
    ];
    text = ''
      # Keep the complete audio value no wider than the longest regular
      # Fastfetch value (the 41-character Date value). The two device names
      # share whatever remains after their labels and volume/mute states.
      max_audio_value_length=41

      truncate_name() {
        local value="$1"
        local max_length="$2"

        awk -v max_length="$max_length" '
          length($0) <= max_length { print; next }
          max_length <= 0 { print ""; next }
          max_length <= 3 { print substr("...", 1, max_length); next }
          {
            prefix_length = max_length - 3
            shortened = substr($0, 1, prefix_length)
            next_character = substr($0, prefix_length + 1, 1)

            # When the cut lands inside a word, prefer the preceding complete
            # word. Keep a character cut for unbroken device names.
            if (shortened !~ /[[:space:]]$/ && next_character !~ /[[:space:]]/) {
              at_boundary = shortened
              sub(/[[:space:]]+[^[:space:]]*$/, "", at_boundary)
              if (at_boundary != "") {
                shortened = at_boundary
              }
            }
            sub(/[[:space:]]+$/, "", shortened)
            print shortened "..."
          }
        ' <<< "$value"
      }

      endpoint_details() {
        local selector="$1"
        local expected_class="$2"
        local inspect associated media_class name volume volume_level percentage

        if ! inspect=$(wpctl inspect "$selector" 2>/dev/null); then
          endpoint_name="Unknown"
          endpoint_suffix=""
          return
        fi

        media_class=$(printf '%s\n' "$inspect" | sed -n 's/.*media.class = "\(.*\)"/\1/p; T; q')
        if [[ -z "$media_class" ]]; then
          endpoint_name="Unknown"
          endpoint_suffix=""
          return
        fi
        if [[ "$media_class" != "$expected_class" ]] || printf '%s\n' "$inspect" | grep -q 'node.virtual = "true"'; then
          endpoint_name="None"
          endpoint_suffix=""
          return
        fi

        if ! associated=$(wpctl inspect --associated "$selector" 2>/dev/null); then
          endpoint_name="Unknown"
          endpoint_suffix=""
          return
        fi
        name=$(printf '%s\n' "$associated" | sed -n 's/.*device.description = "\(.*\)"/\1/p; T; q')
        if [[ -z "$name" ]]; then
          name=$(printf '%s\n' "$inspect" | sed -n 's/.*node.description = "\(.*\)"/\1/p; T; q')
        fi
        if [[ -z "$name" ]]; then
          endpoint_name="Unknown"
          endpoint_suffix=""
          return
        fi

        if ! volume=$(wpctl get-volume "$selector" 2>/dev/null); then
          endpoint_name="Unknown"
          endpoint_suffix=""
          return
        fi
        if ! volume_level=$(awk '$1 == "Volume:" && $2 ~ /^[0-9]+([.][0-9]+)?$/ { print $2; found = 1 } END { if (!found) exit 1 }' <<< "$volume"); then
          endpoint_name="Unknown"
          endpoint_suffix=""
          return
        fi
        percentage=$(awk '{ printf "%.0f", $1 * 100 }' <<< "$volume_level")

        endpoint_name="$name"
        endpoint_suffix=" $percentage%"
        if [[ "$volume" == *"[MUTED]"* ]]; then
          endpoint_suffix+=' (muted)'
        fi
      }

      endpoint_details '@DEFAULT_AUDIO_SINK@' 'Audio/Sink'
      output_name="$endpoint_name"
      output_suffix="$endpoint_suffix"
      endpoint_details '@DEFAULT_AUDIO_SOURCE@' 'Audio/Source'
      input_name="$endpoint_name"
      input_suffix="$endpoint_suffix"

      fixed_length=$((18 + ''${#output_suffix} + ''${#input_suffix}))
      remaining_length=$((max_audio_value_length - fixed_length))
      if (( remaining_length < 0 )); then
        remaining_length=0
      fi

      output_budget=$((remaining_length / 2))
      input_budget=$((remaining_length - output_budget))
      if (( ''${#output_name} < output_budget )); then
        input_budget=$((input_budget + output_budget - ''${#output_name}))
        output_budget=''${#output_name}
      elif (( ''${#input_name} < input_budget )); then
        output_budget=$((output_budget + input_budget - ''${#input_name}))
        input_budget=''${#input_name}
      fi

      output_name=$(truncate_name "$output_name" "$output_budget")
      input_name=$(truncate_name "$input_name" "$input_budget")
      printf 'Output: %s%s | Input: %s%s\n' "$output_name" "$output_suffix" "$input_name" "$input_suffix"
    '';
  };
in

{
  home.packages = [ fastfetchAudio ];

  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      logo = {
        source = "${../../logo/escher-small}";
      };
      modules = [
        "Title"
        "Separator"
        {
          type = "command";
          key = "Date";
          text = "echo \"$(TZ='Asia/Shanghai' date +'%Y-%m-%d (%A)') | $(TZ='Europe/London' date +'%Y-%m-%d (%A)')\"";
        }
        {
          type = "command";
          key = "Time";
          text = "echo \"$(TZ='Asia/Shanghai' date +'%H:%M:%S') | $(TZ='Europe/London' date +'%H:%M:%S')\"";
        }
        "OS"
        "Disk"
        "Memory"
        "Battery"
        "Wifi"
        "Bluetooth"
        {
          type = "command";
          key = "Audio Device";
          text = "fastfetch-audio";
        }
        {
          type = "command";
          key = "Mihomo";
          text = "status=$(systemctl is-active mihomo 2>/dev/null); if [ \"$status\" = \"active\" ]; then config=$(curl -s http://127.0.0.1:9090/configs 2>/dev/null); mode=$(echo \"$config\" | jq -r '.mode' 2>/dev/null); tun=$(echo \"$config\" | jq -r 'if .tun.enable then \"TUN\" else \"noTUN\" end' 2>/dev/null); proxy=$(curl -s http://127.0.0.1:9090/proxies 2>/dev/null | jq -r '[.proxies | to_entries[] | select(.value.type == \"Selector\" and .key != \"GLOBAL\")] | .[0].value.now' 2>/dev/null); echo \"$mode | $proxy | $tun\"; else echo \"inactive\"; fi";
        }
        "Break"
      ];
    };
  };

  # Poems config
  home.file.".config/welcome-poems".source = ../../welcome/poems_short;
}
