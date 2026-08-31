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
  fastfetchBluetooth = pkgs.writeShellApplication {
    name = "fastfetch-bluetooth";
    runtimeInputs = with pkgs; [
      bluez
      coreutils
      gnugrep
      gnused
    ];
    text = ''
      # Connected devices, one indented row each, in the same shape as the
      # Tailnet block. bluetoothctl is local D-Bus IPC and answers in ~15ms
      # while bluetoothd is up, but with bluetooth.service stopped it waits for
      # org.bluez to appear on the bus indefinitely rather than failing -- so
      # every call is bounded by a timeout, and this producer rides the status
      # cache so that wait can never land on a shell's startup path.
      #
      # With nothing connected the whole section disappears, header included,
      # the way the built-in Bluetooth module behaved. Fastfetch drops a
      # `command` module whose output is empty or whitespace-only, so the block
      # is emitted by a blank-key module that carries its own "Bluetooth:"
      # header (see modules below) and a producer that can print nothing at
      # all. Nothing-to-show is spelled `hidden` rather than an empty string so
      # the status cache keeps its "a cache file is never empty" invariant and
      # a crashed producer still reads as a miss; fastfetch-status turns the
      # sentinel back into no output.
      indent='                     '

      # No adapter at all: sysfs answers without touching the bus, so a machine
      # without Bluetooth hardware never pays the timeout. The probe is a plain
      # glob rather than `compgen -G`: writeShellApplication runs the script
      # under bashNonInteractive, which is built --disable-progcomp and so has
      # no compgen builtin at all. That form exits 127 on both hosts and
      # reports every adapter missing, including one with devices connected.
      # An unmatched glob stays literal, and -e on the literal then fails.
      adapters=(/sys/class/bluetooth/*)
      if [[ ! -e "''${adapters[0]}" ]]; then
        printf 'hidden\n'
        exit 0
      fi

      # A timeout or a crash here means bluetoothd is unreachable. That is a
      # different thing from an adapter with nothing connected to it, but both
      # render the same way -- as nothing.
      if ! devices=$(timeout 1s bluetoothctl devices Connected 2>/dev/null); then
        printf 'hidden\n'
        exit 0
      fi
      devices=$(printf '%s\n' "$devices" | grep '^Device ' || true)
      if [[ -z "$devices" ]]; then
        printf 'hidden\n'
        exit 0
      fi

      # Pass one: name and battery per device. The name is the rest of the
      # line, so names containing spaces ("HK Aura Studio 3") survive intact.
      rows=""
      while read -r _device mac name; do
        if [[ -z "$mac" || -z "$name" ]]; then
          continue
        fi
        info=$(timeout 1s bluetoothctl info "$mac" 2>/dev/null || true)
        # "Battery Percentage: 0x5a (90)" -- the decimal in parentheses, the
        # same org.bluez Battery1 property the built-in module read. Absent for
        # devices that expose no battery service.
        percent=$(printf '%s\n' "$info" |
          sed -n 's/.*Battery Percentage:[^(]*(\([0-9][0-9]*\)).*/\1/p' | head -n1)
        rows+="$name"$'\t'"$percent"$'\n'
      done <<< "$devices"
      rows=''${rows%$'\n'}
      if [[ -z "$rows" ]]; then
        printf 'hidden\n'
        exit 0
      fi

      name_width=0
      while IFS=$'\t' read -r name _percent; do
        if (( ''${#name} > name_width )); then
          name_width=''${#name}
        fi
      done <<< "$rows"

      # Battery is higher-is-better, so it takes the same severity ladder the
      # codexbar block uses -- Fastfetch's own polarity and thresholds as ANSI
      # slots, so a phosphor switch carries them. This keeps the colour the
      # built-in Bluetooth module used to apply to the very same figure.
      set_rung() {
        if (( $1 >= 50 )); then
          rung=34 # accent, 5.5:1 -- healthy, recedes behind the value
        elif (( $1 >= 20 )); then
          rung=94 # bright, 9.6:1 -- rises above ordinary text
        else
          rung=92 # hot, 13.1:1 -- the top rung, reserved for alarm
        fi
      }

      # Every row is a connected device, so the bullet is always filled -- ○ is
      # deliberately unused. Paired-but-disconnected devices are not listed
      # (the built-in module hid them too): the pairing list is durable and
      # mostly stale, so on a desktop it is a standing column of hollow bullets
      # for hardware that is switched off, which is noise rather than signal.
      #
      # The leading empty line is the separator above the block, exactly as in
      # the codexbar producer: it belongs to this module, so it leaves with it.
      # The header is printed here rather than being a fastfetch key because
      # only a keyless module can vanish cleanly; fastfetch pads a module's
      # first line to the logo column but emits continuation lines verbatim,
      # so the header takes the same indent as the rows -- which is where
      # fastfetch puts its own keys, as the Tailnet block above shows.
      printf '\n%sBluetooth:\n' "$indent"
      while IFS=$'\t' read -r name percent; do
        if [[ -z "$name" ]]; then
          continue
        fi
        if [[ -n "$percent" ]]; then
          set_rung "$percent"
          printf '%s● %-*s \033[%sm%s%%\033[m\n' "$indent" "$name_width" "$name" "$rung" "$percent"
        else
          # No battery service: no padding and no empty detail column.
          printf '%s● %s\n' "$indent" "$name"
        fi
      done <<< "$rows"
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

  fastfetchQwen = pkgs.writeShellApplication {
    name = "fastfetch-qwen";
    runtimeInputs = with pkgs; [
      aliyun-cli
      coreutils
      jq
    ];
    text = ''
      credentials_path="''${FASTFETCH_QWEN_CREDENTIALS:-${config.home.homeDirectory}/.local/share/hyprwhspr/credentials}"
      aliyun_cli="''${FASTFETCH_QWEN_ALIYUN_CLI:-aliyun}"

      # The activation that installs this shared credential uses mode 0600.
      # Refuse more permissive or malformed files rather than transmitting an
      # AccessKey from an unexpectedly exposed source.
      if [[ ! -f "$credentials_path" ]] || [[ $(stat -Lc '%a' "$credentials_path" 2>/dev/null || true) != 600 ]]; then
        exit 1
      fi
      mapfile -t credentials < <(jq -ser '
        def valid_secret:
          type == "string"
          and length > 0
          and length <= 256
          and ((contains("\n") or contains("\r")) | not);

        if length == 1
           and (.[0] | type == "object")
           and (.[0].aliyun_access_key_id | valid_secret)
           and (.[0].aliyun_access_key_secret | valid_secret)
        then .[0] | .aliyun_access_key_id, .aliyun_access_key_secret
        else empty
        end
      ' "$credentials_path" 2>/dev/null)
      if [[ ''${#credentials[@]} -ne 2 ]]; then
        exit 1
      fi
      access_key_id="''${credentials[0]}"
      access_key_secret="''${credentials[1]}"

      # The official CLI signs the RPC request. Credentials stay in its
      # environment rather than argv, config, logs, or the Fastfetch cache.
      # Clear every inherited alias that can select a profile or make the CLI
      # auto-detect STS, RamRoleArn, or Anonymous instead of static-AK mode.
      unset \
        DEBUG \
        ALIBABA_CLOUD_PROFILE \
        ALIBABACLOUD_PROFILE \
        ALICLOUD_PROFILE \
        ALIBABA_CLOUD_SECURITY_TOKEN \
        ALIBABACLOUD_SECURITY_TOKEN \
        ALICLOUD_SECURITY_TOKEN \
        SECURITY_TOKEN \
        ALIBABA_CLOUD_ROLE_ARN \
        ALIBABACLOUD_ROLE_ARN \
        ALIBABA_CLOUD_PROFILE_MODE
      export ALIBABA_CLOUD_ACCESS_KEY_ID="$access_key_id"
      export ALIBABA_CLOUD_ACCESS_KEY_SECRET="$access_key_secret"
      export ALIBABA_CLOUD_IGNORE_PROFILE=TRUE

      if ! response=$(timeout --signal=TERM --kill-after=1s 5s \
        "$aliyun_cli" bssopenapi QueryAccountBalance \
          --region cn-hangzhou \
          --endpoint business.aliyuncs.com \
          --connect-timeout 2 \
          --read-timeout 3 \
          --retry-count 0 2>/dev/null); then
        unset ALIBABA_CLOUD_ACCESS_KEY_ID ALIBABA_CLOUD_ACCESS_KEY_SECRET
        exit 1
      fi
      unset ALIBABA_CLOUD_ACCESS_KEY_ID ALIBABA_CLOUD_ACCESS_KEY_SECRET

      # Only a validated scalar reaches the cache; never persist or echo the
      # raw billing response. QueryAccountBalance identifies the China account
      # currency explicitly, so a non-CNY response is not relabelled.
      available_cash=$(jq -ser '
        if length == 1 and (.[0] | type == "object")
        then .[0]
          | select(.Success == true)
          | .Data
          | select(type == "object" and .Currency == "CNY")
          | .AvailableCashAmount
          | select(type == "string" and length <= 64)
          | select(test("^-?[0-9]+([.][0-9]+)?$"))
        else empty
        end
      ' <<< "$response" 2>/dev/null) || exit 1
      printf 'CNY %s cash\n' "$available_cash"
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
      fastfetchBluetooth
      fastfetchMihomo
      fastfetchQwen
      fastfetchTailnet
    ];
    text = ''
      cache_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/fastfetch-status"
      install -d -m 700 "$cache_dir"
      refresh() {
        local name="$1" preserve_last_good="''${2:-false}" tmp error_tmp
        tmp=$(mktemp "$cache_dir/.$name.XXXXXX")
        if "fastfetch-$name" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
          mv -f "$tmp" "$cache_dir/$name.txt"
          rm -f "$cache_dir/$name.error"
        else
          rm -f "$tmp"
          if [[ "$preserve_last_good" == true ]]; then
            error_tmp=$(mktemp "$cache_dir/.$name.error.XXXXXX")
            printf 'failed\n' > "$error_tmp"
            mv -f "$error_tmp" "$cache_dir/$name.error"
          fi
        fi
      }
      # Audio is local IPC, not network, but its six serial wpctl round-trips
      # cost ~350ms — by far the greeting's biggest line item — so it rides
      # the same cache. Volume shown can be up to a refresh interval stale.
      #
      # Bluetooth is cached for a different reason: bluetoothctl answers in
      # ~15ms while bluetoothd is up, but with bluetooth.service stopped it
      # blocks waiting for org.bluez rather than failing, so its bounded 1s
      # wait must land here and never on a shell's startup path.
      #
      # No arguments refreshes every producer, which is the timer's job. Named
      # producers refresh only those: a mute is a state change the greeting
      # should show immediately, so the mute watcher (home/desktop/audio-mute-
      # notify.nix) asks for `audio` alone rather than paying for five.
      producers=("$@")
      if [[ ''${#producers[@]} -eq 0 ]]; then
        producers=(audio bluetooth mihomo qwen tailnet)
      fi
      for producer in "''${producers[@]}"; do
        case "$producer" in
          qwen) refresh qwen true & ;;
          audio | bluetooth | mihomo | tailnet) refresh "$producer" & ;;
          *)
            printf 'unknown producer: %s\n' "$producer" >&2
            exit 1
            ;;
        esac
      done
      wait
    '';
  };

  fastfetchStatus = pkgs.writeShellApplication {
    name = "fastfetch-status";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.systemd
    ];
    text = ''
      # Read a cache written by fastfetch-status-refresh. On a miss (first
      # shell right after login, before the timer's first run) show a pending
      # marker and kick the refresh unit so the next shell has real data.
      name="$1"
      cache_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/fastfetch-status"
      cache="$cache_dir/$name.txt"
      error="$cache_dir/$name.error"
      if [ -r "$cache" ]; then
        if [[ "$name" == audio ]]; then
          audio=$(cat "$cache")
          qwen_cache="$cache_dir/qwen.txt"
          qwen_alert=""
          # The producer caps the amount at 64 ASCII characters, so the whole
          # cache is at most 74 bytes including its fixed text and newline.
          if qwen_size=$(stat -Lc '%s' "$qwen_cache" 2>/dev/null) \
             && [[ "$qwen_size" =~ ^[0-9]+$ ]] \
             && ((qwen_size <= 74)) \
             && balance_state=$(LC_ALL=C awk '
            NR == 1 && /^CNY -?[0-9]+([.][0-9]+)? cash$/ {
              valid = 1
              amount = $0
              sub(/^CNY /, "", amount)
              sub(/ cash$/, "", amount)
              if (length(amount) > 64) valid = 0
              next
            }
            { valid = 0 }
            END {
              if (NR != 1 || !valid) exit 1
              negative = sub(/^-/, "", amount)
              part_count = split(amount, decimal_parts, /[.]/)
              integer_part = decimal_parts[1]
              fraction_part = part_count == 2 ? decimal_parts[2] : ""
              sub(/^0+/, "", integer_part)
              sub(/^0+/, "", fraction_part)

              if (integer_part == "" && fraction_part == "") print "out"
              else if (negative) print "out"
              else if (integer_part == "" || integer_part == "1" || integer_part == "2") print "low"
            }
          ' "$qwen_cache" 2>/dev/null); then
            if [[ "$balance_state" == out ]]; then
              qwen_alert=$'\033[92m(Qwen Out)\033[m'
            elif [[ "$balance_state" == low ]]; then
              qwen_alert=$'\033[94m(Qwen Low)\033[m'
            fi
          fi

          # Keep the balance alert beside the input status in both split Audio
          # layouts. When one shared device has identical input/output details,
          # there is no delimiter, so append the alert instead of hiding it.
          if [[ -n "$qwen_alert" && "$audio" == *' | In '* ]]; then
            printf '%s | In %s %s\n' \
              "''${audio%%' | In '*}" "$qwen_alert" "''${audio#*' | In '}"
          elif [[ -n "$qwen_alert" && "$audio" == *' | Input: '* ]]; then
            printf '%s | Input: %s %s\n' \
              "''${audio%%' | Input: '*}" "$qwen_alert" "''${audio#*' | Input: '}"
          elif [[ -n "$qwen_alert" ]]; then
            printf '%s %s\n' "$audio" "$qwen_alert"
          else
            printf '%s\n' "$audio"
          fi
        elif [[ "$name" == qwen && -e "$error" ]]; then
          printf '%s · stale\n' "$(cat "$cache")"
        elif [[ "$name" == bluetooth ]]; then
          # `hidden` is the Bluetooth producer's nothing-to-show sentinel.
          # Printing nothing makes fastfetch drop the whole module, header
          # included. Emitted byte-for-byte otherwise: the block's own first
          # line is empty, so it can never collide with the sentinel.
          if [[ "$(head -n1 "$cache")" != hidden ]]; then
            cat "$cache"
          fi
        else
          cat "$cache"
        fi
      elif [[ "$name" == qwen && -e "$error" ]]; then
        echo "unavailable"
      else
        systemctl --user start --no-block fastfetch-status-refresh.service 2>/dev/null || true
        # Bluetooth is absent unless something is connected, so a pending
        # marker would be the one time the block appears on a machine that
        # otherwise never shows it. Stay silent; the next shell has real data.
        if [[ "$name" != bluetooth ]]; then
          echo "…"
        fi
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
      # block, with remaining quota and reset countdowns.
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

      codex_left5="''${codex[1]}"
      codex_left7="''${codex[2]}"
      claude_left5="''${claude[1]}"
      claude_left7="''${claude[2]}"
      codex_reset5=$(countdown "''${codex[3]}")
      codex_reset7=$(countdown "''${codex[4]}")
      claude_reset5=$(countdown "''${claude[3]}")
      claude_reset7=$(countdown "''${claude[4]}")

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
      # The health signal is the remaining quota, so the severity ramp belongs
      # on the figures -- the same ladder Fastfetch applies to every other
      # percentage in the greeting (see display.percent.color below). These are
      # "higher is better" values, so they take Fastfetch's own polarity and
      # thresholds. ANSI slots rather than hues, so a phosphor switch keeps the
      # ordering in both terminal palettes.
      set_rung() {
        local pct="''${1%\%}"
        if [[ "$1" != *% ]]; then
          rung=39 # default foreground -- N/A is absent data, not a health level
        elif (( pct >= 50 )); then
          rung=34 # accent, 5.5:1 -- healthy, recedes behind the value
        elif (( pct >= 20 )); then
          rung=94 # bright, 9.6:1 -- rises above ordinary text
        else
          rung=92 # hot, 13.1:1 -- the top rung, reserved for alarm
        fi
      }

      row() {
        local state="$1" name="$2" left5="$3" reset5="$4" left7="$5" reset7="$6"
        local bullet rung separator=
        # Shape alone carries quota available/spent for the coding-agent rows,
        # matching the identical glyph in the Tailnet block above.
        if [[ "$state" == ok ]]; then
          bullet='●'
        else
          bullet='○'
        fi
        if [[ "$state" == unavailable ]]; then
          printf '%s%s %-*s \033[94munavailable\033[m\n' "$indent" "$bullet" "$name_width" "$name"
          return
        fi
        printf '%s%s %-*s ' "$indent" "$bullet" "$name_width" "$name"
        if [[ -n "$left5" ]]; then
          set_rung "$left5"
          printf '5h \033[%sm%s\033[m' "$rung" "$left5"
          if [[ -n "$reset5" ]]; then
            printf ' %s' "$reset5"
          fi
          separator=' · '
        fi
        if [[ -n "$left7" ]]; then
          set_rung "$left7"
          printf '%s7d \033[%sm%s\033[m' "$separator" "$rung" "$left7"
          if [[ -n "$reset7" ]]; then
            printf ' %s' "$reset7"
          fi
        fi
        printf '\n'
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
    fastfetchBluetooth
    fastfetchTailnet
    fastfetchMihomo
    fastfetchQwen
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
        "Memory"
        "Battery"
        {
          type = "wifi";
          format = "{ssid} - {protocol} - {band} GHz ({signal-quality})";
        }
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
        # Replaces the built-in Bluetooth module's numbered one-line-per-device
        # rows with the same header-plus-indented-bullets block the Tailnet and
        # codexbar sections use, and like the built-in module it is absent when
        # nothing is connected. Fastfetch drops a `command` module that prints
        # nothing, so the key is blank and the producer emits its own header
        # and its own leading blank line -- both then leave with the block. The
        # Break below is unconditional, which is what keeps exactly one blank
        # line above Tailnet whether or not this block rendered.
        {
          type = "command";
          key = " ";
          text = "fastfetch-status bluetooth";
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

  # Audio alone, for the event-driven path: the mute watcher starts this with
  # --no-block so the ~350ms refresh never delays its notification. A unit
  # rather than a direct call keeps the cache's producer list owned by this
  # module, the same indirection fastfetch-status already uses on a cache miss.
  systemd.user.services.fastfetch-status-refresh-audio = {
    Unit.Description = "Refresh the shell greeting's audio status cache";
    Service = {
      Type = "oneshot";
      ExecStart = "${fastfetchStatusRefresh}/bin/fastfetch-status-refresh audio";
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
