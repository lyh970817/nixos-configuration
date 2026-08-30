{
  writeShellApplication,
  coreutils,
  gnugrep,
  gnused,
  hyprland,
  jq,
  libnotify,
  util-linux,
}:

writeShellApplication {
  name = "screen-shader";
  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    hyprland
    jq
    libnotify
    util-linux
  ];
  text = ''
    state_root="''${XDG_STATE_HOME:-$HOME/.local/state}/screen-shader"
    preference_file="$state_root/preference"
    source_shader="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr/shaders/panel.glsl"
    empty_shader='[[EMPTY]]'
    target_marker='-2147483647'
    command="''${1:-}"
    runtime_base="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"

    notify_message() {
      local urgency="$1" body="$2"
      notify-send -u "$urgency" \
        -h string:x-canonical-private-synchronous:screen-shader \
        "Screen shader" "$body" > /dev/null 2>&1 || true
    }

    # Supervise fresh reconciliations rather than retaining one compositor
    # identity forever. If Hyprland restarts without the graphical-session
    # target cycling, the next pass discovers and locks the new sole instance.
    if [[ "$command" == watch ]]; then
      if (( $# != 1 )); then
        printf 'Usage: screen-shader watch\n' >&2
        exit 2
      fi
      while true; do
        env -u HYPRLAND_INSTANCE_SIGNATURE "$0" reconcile --quiet || true
        sleep 2
      done
    fi

    resolve_instance() {
      local candidate instances_json
      local -a candidates=() live_instances=()

      candidate="''${HYPRLAND_INSTANCE_SIGNATURE:-}"
      if [[ -n "$candidate" && "$candidate" != */* && -S "$runtime_base/$candidate/.socket.sock" ]]; then
        signature="$candidate"
        return 0
      fi

      if ! instances_json="$(hyprctl instances -j 2> /dev/null)" \
        || ! printf '%s' "$instances_json" | jq -e '
          type == "array" and all(.[];
            type == "object" and (.instance | type == "string"))
        ' > /dev/null 2>&1; then
        instance_error="Could not discover a live Hyprland instance"
        return 1
      fi

      mapfile -t candidates < <(printf '%s' "$instances_json" | jq -r '.[].instance')
      for candidate in "''${candidates[@]}"; do
        if [[ -n "$candidate" && "$candidate" != */* && -S "$runtime_base/$candidate/.socket.sock" ]]; then
          live_instances+=("$candidate")
        fi
      done

      if (( ''${#live_instances[@]} != 1 )); then
        instance_error="Expected one live Hyprland instance, found ''${#live_instances[@]}"
        return 1
      fi

      signature="''${live_instances[0]}"
      export HYPRLAND_INSTANCE_SIGNATURE="$signature"
    }

    if ! resolve_instance; then
      printf 'screen-shader: %s\n' "$instance_error" >&2
      if [[ "$command" == toggle ]]; then
        notify_message critical "$instance_error"
      fi
      exit 1
    fi

    runtime_root="$runtime_base/$signature/screen-shader"
    generated_shader="$runtime_root/panel.glsl"
    generated_metadata="$runtime_root/panel.meta"
    failure_fingerprints="$runtime_root/failures"

    mkdir -p "$runtime_root"
    chmod 0700 "$runtime_root"

    lock_controller() {
      exec 9> "$runtime_root/lock"
      flock 9
    }

    unlock_controller() {
      flock -u 9
      exec 9>&-
    }

    report_failure() {
      local manual="$1" code="$2" body="$3" fingerprint
      printf 'screen-shader: %s\n' "$body" >&2

      if [[ "$manual" == true ]]; then
        notify_message critical "$body"
        return 1
      fi

      fingerprint="$(printf '%s\0%s' "$code" "$body" | sha256sum | cut -d ' ' -f 1)"
      if [[ ! -f "$failure_fingerprints" ]] || ! grep -Fxq "$fingerprint" "$failure_fingerprints"; then
        notify_message critical "$body"
        printf '%s\n' "$fingerprint" >> "$failure_fingerprints"
      fi
      return 1
    }

    clear_failures() {
      rm -f "$failure_fingerprints"
    }

    read_preference() {
      if [[ ! -e "$preference_file" ]]; then
        preference=enabled
        return 0
      fi
      preference="$(< "$preference_file")"
      case "$preference" in
      enabled | disabled) return 0 ;;
      *) return 1 ;;
      esac
    }

    current_mode() {
      local requested="$1" target
      if [[ -n "$requested" ]]; then
        mode="$requested"
        return 0
      fi

      target="$(readlink "''${XDG_STATE_HOME:-$HOME/.local/state}/hypr/current-theme.lua" 2> /dev/null || true)"
      case "$target" in
      *dark.lua) mode=dark ;;
      *) mode=light ;;
      esac
    }

    query_monitors() {
      if ! monitors_json="$(hyprctl -j monitors 2> /dev/null)"; then
        return 1
      fi
      printf '%s' "$monitors_json" | jq -e '
        type == "array" and all(.[];
          type == "object"
          and (.name | type == "string")
          and (.id | type == "number")
          and (.id == (.id | floor)))
      ' > /dev/null 2>&1 || return 2
    }

    find_edp() {
      edp_id="$(printf '%s' "$monitors_json" | jq -r '
        first(.[] | select(.name == "eDP-1") | .id) // empty
      ')"
      case "$edp_id" in
      "") has_edp=false ;;
      *[!0-9]*) return 1 ;;
      *) has_edp=true ;;
      esac
    }

    generate_shader() {
      local source_hash wanted_metadata marker_count shader_tmp metadata_tmp
      regenerated=false

      if [[ ! -r "$source_shader" ]]; then
        return 1
      fi
      marker_count="$(grep -Fo -- "$target_marker" "$source_shader" | wc -l || true)"
      if [[ "$marker_count" != 1 ]]; then
        return 2
      fi

      source_hash="$(sha256sum "$source_shader" | cut -d ' ' -f 1)" || return 3
      wanted_metadata="$source_hash $edp_id"
      if [[ -r "$generated_shader" && -r "$generated_metadata" ]] \
        && [[ "$(< "$generated_metadata")" == "$wanted_metadata" ]]; then
        return 0
      fi

      shader_tmp="$(mktemp "$runtime_root/panel.glsl.XXXXXX")" || return 3
      if ! metadata_tmp="$(mktemp "$runtime_root/panel.meta.XXXXXX")"; then
        rm -f "$shader_tmp"
        return 3
      fi
      if ! sed "s/$target_marker/$edp_id/" "$source_shader" > "$shader_tmp" \
        || ! printf '%s\n' "$wanted_metadata" > "$metadata_tmp" \
        || ! chmod 0600 "$shader_tmp" "$metadata_tmp" \
        || ! mv -f "$shader_tmp" "$generated_shader" \
        || ! mv -f "$metadata_tmp" "$generated_metadata"; then
        rm -f "$shader_tmp" "$metadata_tmp"
        return 3
      fi
      regenerated=true
    }

    query_live_shader() {
      local option_json
      if ! option_json="$(hyprctl -j getoption decoration:screen_shader 2> /dev/null)"; then
        return 1
      fi
      live_shader="$(printf '%s' "$option_json" | jq -er '
        if type == "object" and has("str") and (.str | type == "string")
        then .str
        else error("missing string option")
        end
      ' 2> /dev/null)" || return 2
    }

    # `hyprctl keyword` is refused outright under Hyprland's Lua config manager
    # ("keyword can't work with non-legacy parsers. Use eval."), so the live
    # option is set by evaluating a Lua string. The value is escaped for a
    # double-quoted Lua literal; a long-bracket literal is not an option here
    # because the sentinel is itself `[[EMPTY]]`.
    #
    # hyprctl exits 0 even when the compositor refuses the call, so the caller
    # reads the option back rather than trusting this status.
    set_live_shader() {
      local desired="$1" escaped
      escaped="''${desired//\\/\\\\}"
      escaped="''${escaped//\"/\\\"}"
      hyprctl eval "hl.config({ decoration = { screen_shader = \"$escaped\" } })" \
        > /dev/null 2>&1
    }

    reconcile_locked() {
      local requested_mode="$1" manual="$2" desired

      if ! read_preference; then
        report_failure "$manual" preference "The saved shader preference is invalid"
        return 1
      fi
      current_mode "$requested_mode"

      monitor_status=0
      query_monitors || monitor_status=$?
      case "$monitor_status" in
      1)
        report_failure "$manual" monitors-query "Could not query active monitors"
        return 1
        ;;
      2)
        report_failure "$manual" monitors-parse "Could not parse the active monitor list"
        return 1
        ;;
      esac
      if ! find_edp; then
        report_failure "$manual" monitors-parse "Could not parse the eDP-1 output ID"
        return 1
      fi

      regenerated=false
      if [[ "$preference" == enabled && "$mode" == dark && "$has_edp" == true ]]; then
        generate_status=0
        generate_shader || generate_status=$?
        if [[ "$generate_status" != 0 ]]; then
          case "$generate_status" in
          1) report_failure "$manual" shader-source "The panel shader is not readable" ;;
          *) report_failure "$manual" shader-generate "Could not generate the output-aware shader" ;;
          esac
          return 1
        fi
        desired="$generated_shader"
      else
        desired="$empty_shader"
      fi

      option_status=0
      query_live_shader || option_status=$?
      case "$option_status" in
      1)
        report_failure "$manual" option-query "Could not query the live shader state"
        return 1
        ;;
      2)
        report_failure "$manual" option-parse "Could not parse the live shader state"
        return 1
        ;;
      esac

      if [[ "$live_shader" != "$desired" || "$regenerated" == true ]]; then
        if ! set_live_shader "$desired"; then
          report_failure "$manual" option-mutation "Could not apply the requested shader state"
          return 1
        fi
        option_status=0
        query_live_shader || option_status=$?
        case "$option_status" in
        1)
          report_failure "$manual" option-verify-query "Could not query the updated shader state"
          return 1
          ;;
        2)
          report_failure "$manual" option-verify-parse "Could not parse the updated shader state"
          return 1
          ;;
        esac
        if [[ "$live_shader" != "$desired" ]]; then
          report_failure "$manual" option-verify "The updated shader state could not be verified"
          return 1
        fi
      fi

      clear_failures
      LAST_MODE="$mode"
      LAST_HAS_EDP="$has_edp"
    }

    reconcile_once() {
      local requested_mode="$1" manual="$2" result=0
      lock_controller
      reconcile_locked "$requested_mode" "$manual" || result=$?
      unlock_controller
      return "$result"
    }

    write_preference() {
      local value="$1" tmp
      mkdir -p "$state_root" || return 1
      chmod 0700 "$state_root" || return 1
      tmp="$(mktemp "$state_root/preference.XXXXXX")" || return 1
      if ! printf '%s\n' "$value" > "$tmp" \
        || ! chmod 0600 "$tmp" \
        || ! mv -f "$tmp" "$preference_file"; then
        rm -f "$tmp"
        return 1
      fi
    }

    usage() {
      printf 'Usage: screen-shader reconcile [--mode dark|light] [--quiet]\n' >&2
      printf '       screen-shader toggle\n' >&2
      printf '       screen-shader watch\n' >&2
      exit 2
    }

    shift || true
    case "$command" in
    reconcile)
      requested_mode=""
      while (( $# )); do
        case "$1" in
        --mode)
          (( $# >= 2 )) || usage
          case "$2" in dark | light) requested_mode="$2" ;; *) usage ;; esac
          shift 2
          ;;
        --quiet) shift ;;
        *) usage ;;
        esac
      done
      reconcile_once "$requested_mode" false
      ;;
    toggle)
      (( $# == 0 )) || usage
      lock_controller
      preference_existed=false
      [[ -e "$preference_file" ]] && preference_existed=true
      if ! read_preference; then
        report_failure true preference "The saved shader preference is invalid"
        exit 1
      fi
      old_preference="$preference"

      option_status=0
      query_live_shader || option_status=$?
      case "$option_status" in
      1)
        report_failure true option-query "Could not query the live shader state"
        exit 1
        ;;
      2)
        report_failure true option-parse "Could not parse the live shader state"
        exit 1
        ;;
      esac
      old_live_shader="$live_shader"

      if [[ "$preference" == enabled ]]; then
        new_preference=disabled
      else
        new_preference=enabled
      fi
      if ! write_preference "$new_preference"; then
        report_failure true preference-write "Could not save the shader preference"
        exit 1
      fi
      if ! reconcile_locked "" true; then
        if [[ "$preference_existed" == true ]]; then
          if ! write_preference "$old_preference"; then
            printf 'screen-shader: could not restore the previous preference\n' >&2
          fi
        else
          rm -f "$preference_file"
        fi

        if ! set_live_shader "$old_live_shader"; then
          printf 'screen-shader: could not restore the previous live shader\n' >&2
        else
          option_status=0
          query_live_shader || option_status=$?
          if [[ "$option_status" != 0 || "$live_shader" != "$old_live_shader" ]]; then
            printf 'screen-shader: could not verify the restored live shader\n' >&2
          fi
        fi
        exit 1
      fi
      unlock_controller
      if [[ "$new_preference" == disabled ]]; then
        notify_message normal "Disabled"
      elif [[ "$LAST_MODE" != dark ]]; then
        notify_message normal "Enabled, currently inactive in light mode"
      elif [[ "$LAST_HAS_EDP" != true ]]; then
        notify_message normal "Enabled, waiting for eDP-1"
      else
        notify_message normal "Enabled on eDP-1"
      fi
      ;;
    *) usage ;;
    esac
  '';
}
