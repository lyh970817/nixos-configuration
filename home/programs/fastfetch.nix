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
      # Emit tab-separated "status<TAB>name<TAB>percentage<TAB>muted" for an
      # endpoint. status is OK, None (wrong class / virtual) or Unknown. name is
      # truncated to its first space-separated token so the entry stays roughly
      # as short as the other fastfetch lines.
      read_endpoint() {
        local selector="$1"
        local expected_class="$2"
        local inspect associated media_class name volume volume_level percentage muted

        if ! inspect=$(wpctl inspect "$selector" 2>/dev/null); then
          printf 'Unknown\t\t\t\n'
          return
        fi

        media_class=$(printf '%s\n' "$inspect" | sed -n 's/.*media.class = "\(.*\)"/\1/p; T; q')
        if [[ -z "$media_class" ]]; then
          printf 'Unknown\t\t\t\n'
          return
        fi
        if [[ "$media_class" != "$expected_class" ]] || printf '%s\n' "$inspect" | grep -q 'node.virtual = "true"'; then
          printf 'None\t\t\t\n'
          return
        fi

        if ! associated=$(wpctl inspect --associated "$selector" 2>/dev/null); then
          printf 'Unknown\t\t\t\n'
          return
        fi
        name=$(printf '%s\n' "$associated" | sed -n 's/.*device.description = "\(.*\)"/\1/p; T; q')
        if [[ -z "$name" ]]; then
          name=$(printf '%s\n' "$inspect" | sed -n 's/.*node.description = "\(.*\)"/\1/p; T; q')
        fi
        if [[ -z "$name" ]]; then
          printf 'Unknown\t\t\t\n'
          return
        fi
        # Keep only the first space-separated token (drop generic profile suffix).
        name="''${name%% *}"

        if ! volume=$(wpctl get-volume "$selector" 2>/dev/null); then
          printf 'Unknown\t\t\t\n'
          return
        fi
        if ! volume_level=$(awk '$1 == "Volume:" && $2 ~ /^[0-9]+([.][0-9]+)?$/ { print $2; found = 1 } END { if (!found) exit 1 }' <<< "$volume"); then
          printf 'Unknown\t\t\t\n'
          return
        fi
        percentage=$(awk '{ printf "%.0f", $1 * 100 }' <<< "$volume_level")

        muted=""
        if [[ "$volume" == *"[MUTED]"* ]]; then
          muted="muted"
        fi

        printf 'OK\t%s\t%s\t%s\n' "$name" "$percentage" "$muted"
      }

      # Render a single endpoint piece for the fallback (non-shared) layout.
      endpoint_piece() {
        local status="$1" name="$2" pct="$3" muted="$4"
        if [[ "$status" == OK ]]; then
          printf '%s %s%%' "$name" "$pct"
          [[ "$muted" == muted ]] && printf ' (muted)'
        else
          printf '%s' "$status"
        fi
      }

      IFS=$'\t' read -r o_status o_name o_pct o_muted < <(read_endpoint '@DEFAULT_AUDIO_SINK@' 'Audio/Sink')
      IFS=$'\t' read -r i_status i_name i_pct i_muted < <(read_endpoint '@DEFAULT_AUDIO_SOURCE@' 'Audio/Source')

      if [[ "$o_status" == OK && "$i_status" == OK && "$o_name" == "$i_name" ]]; then
        # Same device on output and input: show the name once, with volumes.
        o_detail="$o_pct%"
        i_detail="$i_pct%"
        [[ "$o_muted" == muted ]] && o_detail="$o_detail (muted)"
        [[ "$i_muted" == muted ]] && i_detail="$i_detail (muted)"
        if [[ "$o_detail" == "$i_detail" ]]; then
          printf '%s %s\n' "$o_name" "$o_detail"
        else
          printf '%s Out %s | In %s\n' "$o_name" "$o_detail" "$i_detail"
        fi
      else
        printf 'Output: %s | Input: %s\n' \
          "$(endpoint_piece "$o_status" "$o_name" "$o_pct" "$o_muted")" \
          "$(endpoint_piece "$i_status" "$i_name" "$i_pct" "$i_muted")"
      fi
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
        {
          type = "wifi";
          format = "{ssid} - {protocol} - {band} GHz ({signal-quality})";
        }
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
