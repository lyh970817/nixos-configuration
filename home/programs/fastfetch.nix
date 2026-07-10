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
      endpoint_value() {
        local selector="$1"
        local expected_class="$2"
        local inspect associated media_class name volume volume_level percentage

        if ! inspect=$(wpctl inspect "$selector" 2>/dev/null); then
          printf 'Unknown'
          return
        fi

        media_class=$(printf '%s\n' "$inspect" | sed -n 's/.*media.class = "\(.*\)"/\1/p; T; q')
        if [[ -z "$media_class" ]]; then
          printf 'Unknown'
          return
        fi
        if [[ "$media_class" != "$expected_class" ]] || printf '%s\n' "$inspect" | grep -q 'node.virtual = "true"'; then
          printf 'None'
          return
        fi

        if ! associated=$(wpctl inspect --associated "$selector" 2>/dev/null); then
          printf 'Unknown'
          return
        fi
        name=$(printf '%s\n' "$associated" | sed -n 's/.*device.description = "\(.*\)"/\1/p; T; q')
        if [[ -z "$name" ]]; then
          name=$(printf '%s\n' "$inspect" | sed -n 's/.*node.description = "\(.*\)"/\1/p; T; q')
        fi
        if [[ -z "$name" ]]; then
          printf 'Unknown'
          return
        fi

        if ! volume=$(wpctl get-volume "$selector" 2>/dev/null); then
          printf 'Unknown'
          return
        fi
        if ! volume_level=$(awk '$1 == "Volume:" && $2 ~ /^[0-9]+([.][0-9]+)?$/ { print $2; found = 1 } END { if (!found) exit 1 }' <<< "$volume"); then
          printf 'Unknown'
          return
        fi
        percentage=$(awk '{ printf "%.0f", $1 * 100 }' <<< "$volume_level")

        printf '%s %s%%' "$name" "$percentage"
        if [[ "$volume" == *"[MUTED]"* ]]; then
          printf ' (muted)'
        fi
      }

      printf 'Output: '
      endpoint_value '@DEFAULT_AUDIO_SINK@' 'Audio/Sink'
      printf ' | Input: '
      endpoint_value '@DEFAULT_AUDIO_SOURCE@' 'Audio/Source'
      printf '\n'
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
