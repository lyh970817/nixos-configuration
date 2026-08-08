{
  config,
  lib,
  pkgs,
  ...
}:

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

        if ! inspect=$(timeout 0.5s wpctl inspect "$selector" 2>/dev/null); then
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

        if ! associated=$(timeout 0.5s wpctl inspect --associated "$selector" 2>/dev/null); then
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

        if ! volume=$(timeout 0.5s wpctl get-volume "$selector" 2>/dev/null); then
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

  fastfetchPeerHome = pkgs.writeShellApplication {
    name = "fastfetch-peer-home";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
    ];
    text = ''
      # statfs on the sshfs peer mount blocks indefinitely when the peer is
      # asleep or the tailnet path is stale, and this runs in every new
      # shell's greeting — so the probe is a plain df under a hard timeout
      # instead of a nested fastfetch disk scan (which also statfs'd every
      # other mount along the way).
      mount_point=${lib.escapeShellArg "${config.home.homeDirectory}/home"}
      if out=$(timeout 0.5 df -B1 --output=fstype,used,size "$mount_point" 2>/dev/null | tail -1) \
          && [ -n "$out" ]; then
        echo "$out" | awk '{ printf "%.2f GiB / %.2f GiB (%.0f%%) - %s\n", $2 / 1073741824, $3 / 1073741824, $2 * 100 / $3, $1 }'
      else
        echo "unavailable"
      fi
    '';
  };

  fastfetchTailnet = pkgs.writeShellApplication {
    name = "fastfetch-tailnet";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      jq
      tailscale
    ];
    text = ''
      status_json=$(timeout 1s tailscale status --json 2>/dev/null || true)
      if [[ -z "$status_json" ]]; then
        printf 'unavailable\n'
        exit 0
      fi

      device_rows=$(printf '%s\n' "$status_json" | jq -r '
        (.Self | . + {_self: true}) as $self |
        ([.Peer // {} | to_entries[] | .value + {_self: false}]) as $peers |
        ([$self] + $peers)[] |
        [
          (.Online // false),
          (.DNSName | rtrimstr(".") | split(".")[0]),
          (._self // false),
          (.Active // false),
          (.LastSeen // "")
        ] | @tsv
      ' 2>/dev/null || true)
      if [[ -z "$device_rows" ]]; then
        printf 'unavailable\n'
        exit 0
      fi

      printf '\n'
      indent='                     '
      name_width=0
      while IFS=$'\t' read -r _online name _self _active _last_seen; do
        if (( ''${#name} > name_width )); then
          name_width=''${#name}
        fi
      done <<< "$device_rows"

      while IFS=$'\t' read -r online_state name is_self active last_seen; do
        symbol='○'
        detail='offline'
        if [[ "$online_state" == true ]]; then
          symbol='●'
          detail='online'
          [[ "$is_self" == true ]] && detail='online · self'
          [[ "$is_self" != true && "$active" == true ]] && detail='online · active'
        elif [[ "$last_seen" != 0001-* && -n "$last_seen" ]]; then
          seen_epoch=$(date -d "$last_seen" +%s 2>/dev/null || true)
          if [[ -n "$seen_epoch" ]]; then
            age_days=$(( ($(date +%s) - seen_epoch) / 86400 ))
            if (( age_days < 1 )); then
              detail='offline · <1d ago'
            else
              detail="offline · ''${age_days}d ago"
            fi
          fi
        fi
        printf "%s%s %-''${name_width}s %s\n" "$indent" "$symbol" "$name" "$detail"
      done <<< "$device_rows"
    '';
  };
  fastfetchMihomo = pkgs.writeShellApplication {
    name = "fastfetch-mihomo";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = ''
      # Probe mihomo's controller. A curl against a down controller fails
      # instantly, so no systemctl gate is needed.
      if ! config=$(curl -s --max-time 2 http://127.0.0.1:9090/configs 2>/dev/null) || [ -z "$config" ]; then
        echo "inactive"
        exit 0
      fi
      mode=$(jq -r '.mode // "?"' <<< "$config")
      tun=$(jq -r 'if .tun.enable then "TUN" else "noTUN" end' <<< "$config")
      proxy=$(curl -s --max-time 2 http://127.0.0.1:9090/proxies 2>/dev/null | jq -r '
        [.proxies | to_entries[] | select(.value.type == "Selector" and .key != "GLOBAL")]
        | .[0].value.now // "?"
      ' 2>/dev/null || echo "?")
      echo "$mode | $proxy | $tun"
    '';
  };

  # The greeting used to probe mihomo and the tailnet inline, which put two
  # network round-trips on every shell's startup path (and their costs are
  # paid serially, in display order). Instead a user timer refreshes small
  # text caches under $XDG_RUNTIME_DIR — the same pattern codexbar already
  # uses — and the greeting only reads files. Runtime dir means the caches
  # die with the session rather than surviving reboots.
  fastfetchStatusRefresh = pkgs.writeShellApplication {
    name = "fastfetch-status-refresh";
    runtimeInputs = [
      pkgs.coreutils
      fastfetchAudio
      fastfetchMihomo
      fastfetchTailnet
    ];
    text = ''
      cache_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/fastfetch-status"
      install -d -m 700 "$cache_dir"
      refresh() {
        local name="$1" tmp
        tmp=$(mktemp "$cache_dir/.$name.XXXXXX")
        if "fastfetch-$name" > "$tmp" 2>/dev/null; then
          mv -f "$tmp" "$cache_dir/$name.txt"
        else
          rm -f "$tmp"
        fi
      }
      # Audio is local IPC, not network, but its six serial wpctl round-trips
      # cost ~350ms — by far the greeting's biggest line item — so it rides
      # the same cache. Volume shown can be up to a refresh interval stale.
      refresh audio &
      refresh mihomo &
      refresh tailnet &
      wait
    '';
  };

  fastfetchStatus = pkgs.writeShellApplication {
    name = "fastfetch-status";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Read a cache written by fastfetch-status-refresh. On a miss (first
      # shell right after login, before the timer's first run) show a pending
      # marker and kick the refresh unit so the next shell has real data.
      name="$1"
      cache="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/fastfetch-status/$name.txt"
      if [ -r "$cache" ]; then
        cat "$cache"
      else
        systemctl --user start --no-block fastfetch-status-refresh.service 2>/dev/null || true
        echo "…"
      fi
    '';
  };

  codexbarCachePath = "${config.home.homeDirectory}/.cache/codexbar/usage.json";
  fastfetchCodexbar = pkgs.writeShellApplication {
    name = "fastfetch-codexbar";
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = ''
      # Renders one indented row per provider, in the same shape as the Tailnet
      # block: a bullet for "has quota left right now", then each window's
      # remaining percentage followed by a countdown to its reset. The windows
      # are always the 5-hour and 7-day ones, so they go unlabelled.
      cache_path=${lib.escapeShellArg codexbarCachePath}
      indent='                     '

      # Emit five lines for one provider: state, 5h remaining, 7d remaining, 5h
      # resetsAt, 7d resetsAt. Line-delimited rather than tab-delimited because
      # bash read collapses runs of tabs, which drops an empty resetsAt field.
      # State is "spent" when either window is used up, which is what turns the
      # bullet hollow; the per-window figures stay truthful either way.
      query() {
        local out
        if [[ -r "$cache_path" ]] && out=$(jq -r --arg provider "$1" '
          def remaining($window):
            if ($window == null or $window.usedPercent == null) then ""
            else ((100 - $window.usedPercent) | round | tostring) + "%"
            end;
          def exhausted($window):
            ($window != null and $window.usedPercent != null and $window.usedPercent >= 100);

          (if type == "array" then . else [.] end)
          | map(select(.provider == $provider))
          | if length == 0 then ["unavailable", "", "", "", ""]
            else .[0] as $entry
            | if $entry.usage == null then ["unavailable", "", "", "", ""]
              else
                [ (if (exhausted($entry.usage.primary) or exhausted($entry.usage.secondary))
                   then "spent" else "ok" end),
                  remaining($entry.usage.primary),
                  remaining($entry.usage.secondary),
                  ($entry.usage.primary.resetsAt // ""),
                  ($entry.usage.secondary.resetsAt // "") ]
              end
            end
          | .[]
        ' "$cache_path" 2>/dev/null) && [[ $(wc -l <<< "$out") -eq 5 ]]; then
          printf '%s\n' "$out"
        else
          printf 'unavailable\n\n\n\n\n'
        fi
      }

      now=$(date +%s)

      # Coarse single-unit countdown in parentheses, empty when the window has
      # no known reset time.
      countdown() {
        local timestamp="$1" target delta days hours minutes
        if [[ -z "$timestamp" ]]; then
          return
        fi
        if ! target=$(date -d "$timestamp" +%s 2>/dev/null); then
          return
        fi
        delta=$(( target - now ))
        if (( delta < 0 )); then
          delta=0
        fi
        days=$(( delta / 86400 ))
        hours=$(( (delta % 86400) / 3600 ))
        minutes=$(( (delta % 3600) / 60 ))
        if (( days > 0 )); then
          printf '(%dd)' "$days"
        elif (( hours > 0 )); then
          printf '(%dh)' "$hours"
        else
          printf '(%dm)' "$minutes"
        fi
      }

      mapfile -t codex < <(query codex)
      mapfile -t claude < <(query claude)

      # A window the provider does not report reads as N/A in both of its
      # columns, so the row keeps its shape instead of leaving a gap.
      na_if_empty() {
        if [[ -z "$1" ]]; then
          printf 'N/A'
        else
          printf '%s' "$1"
        fi
      }
      codex_left5=$(na_if_empty "''${codex[1]}")
      codex_left7=$(na_if_empty "''${codex[2]}")
      claude_left5=$(na_if_empty "''${claude[1]}")
      claude_left7=$(na_if_empty "''${claude[2]}")
      codex_reset5=$(na_if_empty "$(countdown "''${codex[3]}")")
      codex_reset7=$(na_if_empty "$(countdown "''${codex[4]}")")
      claude_reset5=$(na_if_empty "$(countdown "''${claude[3]}")")
      claude_reset7=$(na_if_empty "$(countdown "''${claude[4]}")")

      widest() {
        local result=0 candidate
        for candidate in "$@"; do
          if (( ''${#candidate} > result )); then
            result=''${#candidate}
          fi
        done
        printf '%d' "$result"
      }
      name_width=$(widest codex claude)
      width_left5=$(widest "$codex_left5" "$claude_left5")
      width_reset5=$(widest "$codex_reset5" "$claude_reset5")
      width_left7=$(widest "$codex_left7" "$claude_left7")

      row() {
        local state="$1" name="$2" left5="$3" reset5="$4" left7="$5" reset7="$6" bullet color
        # Keep the marker's shape semantics (filled means usable, hollow means
        # not) and give its actual CodexBar state the same severity ladder as
        # Fastfetch percentages: available is the receding accent; unavailable
        # is bright so stale/missing data is noticeable; a spent window is hot.
        # These are ANSI slots rather than hues, so phosphor switching preserves
        # the health ordering in both terminal palettes.
        case "$state" in
          ok) color=34; bullet='●' ;;
          unavailable) color=94; bullet='○' ;;
          *) color=92; bullet='○' ;;
        esac
        bullet=$(printf '\033[%sm%s\033[0m' "$color" "$bullet")
        if [[ "$state" == unavailable ]]; then
          printf '%s%s %-*s unavailable\n' "$indent" "$bullet" "$name_width" "$name"
          return
        fi
        printf '%s%s %-*s %*s %-*s · %*s %s\n' \
          "$indent" "$bullet" "$name_width" "$name" \
          "$width_left5" "$left5" "$width_reset5" "$reset5" \
          "$width_left7" "$left7" "$reset7"
      }

      printf '\n'
      row "''${codex[0]}" codex "$codex_left5" "$codex_reset5" "$codex_left7" "$codex_reset7"
      row "''${claude[0]}" claude "$claude_left5" "$claude_reset5" "$claude_left7" "$claude_reset7"
    '';
  };

in
{
  home.packages = [
    fastfetchAudio
    fastfetchPeerHome
    fastfetchTailnet
    fastfetchMihomo
    fastfetchStatus
    fastfetchCodexbar
  ];

  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json";
      logo = {
        source = "${../../logo/escher-small}";
      };

      # Percentages are the one place fastfetch reaches for hue: it picks
      # green/yellow/red by how alarming the value is. A single-phosphor
      # palette has no hue to give, so the three states are remapped onto SGR
      # codes whose terminal slots climb the ladder instead -- severity as
      # intensity, which is the only channel left. Codes rather than hexes, so
      # a phosphor switch carries them; see home/palettes.nix and the slot
      # assignments in programs/foot.nix.
      #
      # The defaults were unusable here: green and red both landed on
      # mutedText (2.5:1 against the background, under even the 3:1 floor), so
      # every parenthesised percentage was the dimmest thing on screen *and*
      # a critical value looked identical to a healthy one. These clear 4.5:1
      # at the bottom and rise from there, staying below the plain value text
      # (7.1:1) when healthy and above it when not.
      display = {
        percent = {
          color = {
            green = "34"; # accent, 5.5:1 -- healthy, recedes behind the value
            yellow = "94"; # bright, 9.6:1 -- rises above ordinary text
            red = "92"; # hot, 13.1:1 -- the top rung, reserved for alarm
          };
        };
      };

      modules = [
        "Title"
        "Separator"
        {
          type = "command";
          key = "Date";
          text = "TZDIR=/etc/zoneinfo TZ='Asia/Shanghai' date +'%Y-%m-%d (%A)'";
        }
        {
          type = "command";
          key = "Time";
          text = "export TZDIR=/etc/zoneinfo; echo \"$(TZ='Asia/Shanghai' date +'%H:%M:%S') | $(TZ='Europe/London' date +'%H:%M:%S')\"";
        }
        "OS"
        {
          type = "disk";
          folders = "/";
        }
        {
          type = "command";
          key = "Disk (~/home)";
          text = "fastfetch-peer-home";
        }
        "Memory"
        "Battery"
        {
          type = "wifi";
          format = "{ssid} - {protocol} - {band} GHz ({signal-quality})";
        }
        "Bluetooth"
        {
          type = "command";
          key = "Audio";
          text = "fastfetch-status audio";
        }
        {
          type = "command";
          key = "Mihomo";
          text = "fastfetch-status mihomo";
        }
        # A blank key renders the block with no header, and supplies the blank
        # line that would otherwise need a Break.
        {
          type = "command";
          key = " ";
          text = "fastfetch-codexbar";
        }
        "Break"
        {
          type = "command";
          key = "Tailnet";
          text = "fastfetch-status tailnet";
        }
        "Break"
      ];
    };
  };

  systemd.user.services.fastfetch-status-refresh = {
    Unit.Description = "Refresh the shell greeting's network status caches";
    Service = {
      Type = "oneshot";
      ExecStart = "${fastfetchStatusRefresh}/bin/fastfetch-status-refresh";
    };
  };

  systemd.user.timers.fastfetch-status-refresh = {
    # No Requires/After on other units: the codexbar-refresh timer showed how
    # an ordering edge back into basic.target gets timers.target dropped from
    # the login transaction. This timer depends on nothing, so it stays bare.
    Unit.Description = "Refresh the shell greeting's network status caches periodically";
    Timer = {
      OnBootSec = "5s";
      OnUnitActiveSec = "60s";
      Unit = "fastfetch-status-refresh.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Poems config
  home.file.".config/welcome-poems".source = ../../welcome/poems_short;
}
