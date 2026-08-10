{
  writeShellApplication,
  coreutils,
  hyprland,
}:

# TRANSITIONAL. Delete this package, and collapse every call site onto plain
# `hyprctl dispatch`/`hyprctl eval`, once every machine has logged out and back
# in at least once on a generation that ships dotfiles/hypr/hyprland.lua --
# i.e. once no compositor anywhere is still running the hyprlang manager. Track
# it with `hypr-ipc manager` on each host: when both print `lua`, this is dead
# weight. See docs in todo.md ("Hyprland Lua migration").
#
# Hyprland picks its config manager once, at startup, from which config file it
# finds; `hyprctl reload` cannot switch it. So a `nixos-rebuild switch` on a
# machine whose compositor started before the migration leaves a *hyprlang*
# compositor running against *Lua*-speaking scripts, and every mutating IPC
# call silently stops working until the user logs out. Measured on Hyprland
# 0.56.1, both directions:
#
#   hyprctl dispatch killactive        -> lua:    error: ... expected a dispatcher
#   hyprctl dispatch 'hl.dsp...'       -> legacy: invalid dispatcher
#   hyprctl keyword general:gaps_in 8  -> lua:    keyword can't work with non-legacy parsers. Use eval.
#   hyprctl eval 'hl.config{...}'      -> legacy: eval is only supported with the lua config manager
#
# hyprctl exits 0 in all four cases, so nothing detects this by status; the
# action just never happens. This shim asks the *running* compositor which
# dialect it speaks and sends that one, so config files and running sessions no
# longer have to agree.
writeShellApplication {
  name = "hypr-ipc";
  runtimeInputs = [
    coreutils
    hyprland
  ];
  text = ''
    runtime_base="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"

    usage() {
      printf 'Usage: hypr-ipc manager\n' >&2
      printf '       hypr-ipc dispatch <lua-expression> -- <legacy hyprctl dispatch args...>\n' >&2
      printf '       hypr-ipc keyword  <lua-expression> -- <legacy hyprctl keyword args...>\n' >&2
      exit 2
    }

    # `hyprctl eval` is the probe rather than `hyprctl systeminfo`, whose
    # `configProvider:` line answers this directly but costs ~440ms because it
    # shells out for GPU/PCI details; the eval round trip is ~20ms and these
    # scripts sit on keypress paths. `return true` evaluates to nothing and
    # mutates nothing. systeminfo is kept as the tiebreaker for an unrecognised
    # reply, because guessing here reintroduces the exact silent no-op this
    # package exists to prevent.
    probe_manager() {
      local reply provider
      reply="$(hyprctl eval 'return true' 2> /dev/null || true)"
      case "$reply" in
      ok*)
        printf 'lua\n'
        return 0
        ;;
      *"lua config manager"*)
        printf 'legacy\n'
        return 0
        ;;
      esac

      provider="$(hyprctl systeminfo 2> /dev/null | sed -n 's/^configProvider:[[:space:]]*//p' | head -n 1)"
      case "$provider" in
      lua) printf 'lua\n' ;;
      hyprlang) printf 'legacy\n' ;;
      # No compositor reachable, or a reply this shim does not know. Answer
      # with the permanent dialect: the transitional one is the one that is
      # going away, so an unknown compositor is more likely to be a new one.
      *) printf 'lua\n' ;;
      esac
    }

    # The answer cannot change within one compositor lifetime -- the manager is
    # chosen at startup -- and HYPRLAND_INSTANCE_SIGNATURE changes when the
    # compositor restarts, so a cache keyed by it can never go stale.
    manager() {
      local cache="" cached=""
      if [[ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" && "$HYPRLAND_INSTANCE_SIGNATURE" != */* ]]; then
        cache="$runtime_base/$HYPRLAND_INSTANCE_SIGNATURE/config-manager"
      fi

      if [[ -n "$cache" && -r "$cache" ]]; then
        read -r cached < "$cache" || cached=""
        case "$cached" in
        lua | legacy)
          printf '%s\n' "$cached"
          return 0
          ;;
        esac
      fi

      cached="$(probe_manager)"
      if [[ -n "$cache" ]]; then
        printf '%s\n' "$cached" > "$cache" 2> /dev/null || true
      fi
      printf '%s\n' "$cached"
    }

    command="''${1:-}"
    shift || usage

    case "$command" in
    manager)
      (( $# == 0 )) || usage
      manager
      ;;
    dispatch | keyword)
      (( $# >= 1 )) || usage
      lua="$1"
      shift
      [[ "''${1:-}" == "--" ]] || usage
      shift
      (( $# >= 1 )) || usage

      # hyprctl's own exit status is passed through unchanged (it is 0 even for
      # the refusals above); callers that need certainty read the state back,
      # as screen-shader-controller does.
      if [[ "$(manager)" == lua ]]; then
        case "$command" in
        dispatch) exec hyprctl dispatch "$lua" ;;
        keyword) exec hyprctl eval "$lua" ;;
        esac
      fi
      exec hyprctl "$command" "$@"
      ;;
    *) usage ;;
    esac
  '';
}
