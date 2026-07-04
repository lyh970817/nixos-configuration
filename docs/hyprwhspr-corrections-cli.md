# Editing hyprwhspr Corrections From the Command Line

hyprwhspr stores custom transcription corrections in:

```sh
~/.config/hyprwhspr/config.json
```

The corrections dictionary is the `word_overrides` object:

```json
{
  "word_overrides": {
    "hyper whisper": "hyprwhspr",
    "kube cuddle": "kubectl",
    "pipe wire": "PipeWire",
    "um": ""
  }
}
```

These are post-transcription corrections. They do not train the speech model and
they are not learned automatically. hyprwhspr applies them after it has produced
text.

## Behavior

- Keys are the text hyprwhspr hears.
- Values are the replacement text.
- An empty string deletes the heard phrase.
- Multi-character keys match whole words or whole phrases.
- Single-character keys can match inside words, for example `"ß": "ss"`.
- Matching is case-insensitive.
- Keep the heard phrase lowercase for predictable editing.
- Replacement values can keep the desired capitalization, for example
  `PipeWire`, `PyTorch`, `GPT-5`, or `kubectl`.

## Built-In Commands

View your explicit config overrides:

```sh
hyprwhspr config show
```

View the resolved config including defaults:

```sh
hyprwhspr config show --all
```

Open the config in an editor:

```sh
hyprwhspr config edit
```

There is no documented public command like `hyprwhspr corrections add`. For
non-interactive editing, edit `config.json` with `jq`.

## Add or Update a Correction

```sh
mkdir -p ~/.config/hyprwhspr
cfg="$HOME/.config/hyprwhspr/config.json"
test -s "$cfg" || printf '{}\n' > "$cfg"

tmp="$(mktemp)"
jq --arg heard "kube cuddle" --arg replacement "kubectl" \
  '.word_overrides = (.word_overrides // {}) | .word_overrides[$heard] = $replacement' \
  "$cfg" > "$tmp" && mv "$tmp" "$cfg"

systemctl --user restart hyprwhspr.service
```

## Add a Deletion Rule

This removes a phrase from the final output:

```sh
cfg="$HOME/.config/hyprwhspr/config.json"
tmp="$(mktemp)"
jq --arg heard "um" --arg replacement "" \
  '.word_overrides = (.word_overrides // {}) | .word_overrides[$heard] = $replacement' \
  "$cfg" > "$tmp" && mv "$tmp" "$cfg"

systemctl --user restart hyprwhspr.service
```

## Remove a Correction

```sh
cfg="$HOME/.config/hyprwhspr/config.json"
tmp="$(mktemp)"
jq --arg heard "kube cuddle" \
  'del(.word_overrides[$heard])' \
  "$cfg" > "$tmp" && mv "$tmp" "$cfg"

systemctl --user restart hyprwhspr.service
```

## List Corrections

```sh
jq '.word_overrides // {}' ~/.config/hyprwhspr/config.json
```

## Shell Helper

Add this to your shell config if you want a short command:

```sh
hyprwhspr-correct() {
  cfg="$HOME/.config/hyprwhspr/config.json"
  mkdir -p "$(dirname "$cfg")"
  test -s "$cfg" || printf '{}\n' > "$cfg"

  heard="$1"
  replacement="$2"

  if [ -z "$heard" ]; then
    echo "usage: hyprwhspr-correct 'heard phrase' 'replacement'"
    return 2
  fi

  tmp="$(mktemp)"
  jq --arg heard "$heard" --arg replacement "$replacement" \
    '.word_overrides = (.word_overrides // {}) | .word_overrides[$heard] = $replacement' \
    "$cfg" > "$tmp" && mv "$tmp" "$cfg"

  systemctl --user restart hyprwhspr.service
}
```

Examples:

```sh
hyprwhspr-correct "kube cuddle" "kubectl"
hyprwhspr-correct "pipe wire" "PipeWire"
hyprwhspr-correct "pie torch" "PyTorch"
hyprwhspr-correct "g p t five" "GPT-5"
hyprwhspr-correct "um" ""
```

## Safer Helper With Remove Support

This version supports `--remove` and checks that `jq` can parse the config
before replacing the file:

```sh
hyprwhspr-correction() {
  cfg="$HOME/.config/hyprwhspr/config.json"
  mkdir -p "$(dirname "$cfg")"
  test -s "$cfg" || printf '{}\n' > "$cfg"

  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required"
    return 127
  fi

  case "$1" in
    --list)
      jq '.word_overrides // {}' "$cfg"
      ;;
    --remove)
      heard="$2"
      if [ -z "$heard" ]; then
        echo "usage: hyprwhspr-correction --remove 'heard phrase'"
        return 2
      fi
      tmp="$(mktemp)"
      jq --arg heard "$heard" 'del(.word_overrides[$heard])' "$cfg" > "$tmp" &&
        mv "$tmp" "$cfg" &&
        systemctl --user restart hyprwhspr.service
      ;;
    *)
      heard="$1"
      replacement="$2"
      if [ -z "$heard" ]; then
        echo "usage: hyprwhspr-correction 'heard phrase' 'replacement'"
        echo "       hyprwhspr-correction --remove 'heard phrase'"
        echo "       hyprwhspr-correction --list"
        return 2
      fi
      tmp="$(mktemp)"
      jq --arg heard "$heard" --arg replacement "$replacement" \
        '.word_overrides = (.word_overrides // {}) | .word_overrides[$heard] = $replacement' \
        "$cfg" > "$tmp" &&
        mv "$tmp" "$cfg" &&
        systemctl --user restart hyprwhspr.service
      ;;
  esac
}
```

Examples:

```sh
hyprwhspr-correction --list
hyprwhspr-correction "post grass" "Postgres"
hyprwhspr-correction "way bar" "Waybar"
hyprwhspr-correction "uh" ""
hyprwhspr-correction --remove "post grass"
```

## JSON Caveat

The `jq` commands require strict JSON. If `~/.config/hyprwhspr/config.json`
contains comments, trailing commas, or other JSONC syntax, `jq` will fail. In
that case, either remove the comments or use:

```sh
hyprwhspr config edit
```

## Applying Changes

Restart the user service after changing `config.json`:

```sh
systemctl --user restart hyprwhspr.service
```

The docs and setup messages commonly show both of these forms:

```sh
systemctl --user restart hyprwhspr
systemctl --user restart hyprwhspr.service
```

Use the `.service` form if you want to be explicit.
