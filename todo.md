# TODO

## Dictation bake-off: audio3 vs qwen3-asr-flash-realtime (fair fight)

**Status:** open, waiting on DashScope top-up (account hit free-quota exhaustion
/ "Access to model denied" on 2026-07-28).

**Context session:** `56fd6974-0e96-49f0-9e73-d5606b16ff78` (resume with
`claude --resume 56fd6974-0e96-49f0-9e73-d5606b16ff78`) — full investigation of
the July DashScope bill, per-model cost math, and why the current
audio3-vs-flash comparison is confounded.

### Task

Determine whether `qwen-audio-3.0-realtime-plus` (~¥0.015/utterance) is really
better than the ~10x cheaper `qwen-ws` path (`qwen3-asr-flash-realtime` ASR +
`qwen3.6-flash` cleanup), or whether the gap is mostly prompt asymmetry:

1. Port the aggressive cleanup prompt (`DEFAULT_AGGRESSIVE_CLEANUP_PROMPT` in
   `scripts/qwen-asr-shim.py`) to the ws route's cleanup stage — today the ws
   route deliberately uses the short conservative prompt, so the comparison is
   unfair.
2. Write a replay script: run archived dictation audio
   (`~/.local/share/hyprwhspr/short/audio/`, 30-day retention) through both
   `/transcribe/ws` and the audio3 route; diff outputs side by side.
3. Decide: if flash+aggressive-prompt is within tolerance on real audio
   (technical terms, mixed Chinese/English), switch the default profile and
   optionally buy the ¥20 speech savings-plan tier (covers Qwen-ASR-Realtime,
   NOT audio3/omni). Otherwise stay on audio3 and top up accordingly
   (~¥2.2/day at ~150 utterances/day).

## Laptop accepts no inbound SSH, so `theme-push` is one-directional

**Status:** open, low priority. Not a regression — it has never worked in this
direction.

### Symptom

Toggling light/dark on the **home desktop** does not change the **laptop**.
Toggling on the laptop does correctly change the desktop.

There is no error message, no hang, and nothing in the logs. The failure is
completely silent by construction.

### Cause

`theme-push` (`home/desktop/theming.nix:112-120`) notifies the peer machine of a
mode change:

```sh
PEER="${peerHost}"
[ -n "$PEER" ] || exit 0
case "$1" in light | dark) ;; *) exit 0 ;; esac
timeout 3 ssh -o ConnectTimeout=2 "$PEER" "switch-$1" >/dev/null 2>&1 &
```

It relies on Tailscale SSH (keyless, authenticated on tailnet identity). But
Tailscale SSH is enabled **only on the home role**:

```nix
# modules/system/networking.nix:47
services.tailscale.extraUpFlags = lib.mkIf (config.portable.role == "home") [ "--ssh" ];
```

So the laptop runs no SSH server of any kind — `services.openssh` is configured
nowhere in the repo either. From the home machine, `ssh "$PEER"` has nothing to
connect to. Because the call is backgrounded, `timeout`-bounded and redirected to
`/dev/null 2>&1`, the failure is invisible.

Only `theme-toggle` (`home/desktop/theming.nix:127`) calls `theme-push` — a
deliberate manual "make everything dark tonight" gesture. Automatic
cross-machine sync on monitor edges was removed on purpose (see the comment at
`theming.nix:107-111`), so this affects one manual convenience only.

### Fix, if wanted

Ungate the flag so the remote role also accepts Tailscale SSH:

```nix
services.tailscale.extraUpFlags = [ "--ssh" ];
```

Note the comment at `networking.nix:43-46`: `extraUpFlags` only takes effect for
auth-key-based `tailscale up`, so this likely also needs a manual
`tailscale up --ssh` once on the laptop.

### Trade-off

This means the laptop accepts inbound shell connections. Specifically:

- **Not** an open port on the public interface. Tailscale SSH lives inside
  `tailscaled` and listens only on the tailnet address; the firewall's
  `trustedInterfaces = [ "Meta" "tailscale0" ]` (`networking.nix:133-136`) is
  what lets tailnet traffic through, and port 22 is not in `allowedTCPPorts`.
- The exposure is "any node on the tailnet, or anyone who compromises the
  Tailscale account" — the same perimeter that already governs mosh and quicktui.
- The laptop is portable and joins untrusted networks (cafés, hotels), which is
  why this is a slightly worse trade than the equivalent on the stationary
  desktop. Tailscale SSH does not listen on those networks' interfaces, so the
  practical risk is the tailnet perimeter, not the local segment.

### Deliberately not required by the yazi SFTP feature

The remote-image-viewing setup (`dotfiles/yazi/vfs.toml`, commit `1c96e25`) runs
laptop → home, the direction that already works. It needs no inbound SSH on the
laptop and no sshd on the desktop. Do not enable either on its account.

## `screen-verify` staging does not isolate keyboard input

**Status:** open. Observed 2026-07-29 during the herdr visual verification pass.

### Symptom

While an agent drove a staged window, the user's **physical** keystrokes went
into that window instead of the app they were looking at. Between roughly 09:44
and 09:48 typed characters landed in an off-screen herdr instance (visible as
stray `fff` / `lf` in captures 005-008), and Hyprland focus jumped to an
unrelated window on its own. Nothing was executed, and focus was restored
afterwards.

### Cause

Staging solves *visual* isolation only: `screen-verify launch` puts test windows
on a hidden staging workspace so they do not disturb the user's view. But there
is exactly one keyboard focus on the seat. Any interaction that needs keys --
`hyprctl dispatch focuswindow` onto the staged window plus `wtype` -- necessarily
moves the real focus there, so the physical keyboard follows. The window is
invisible, so the user gets no feedback that their typing is going somewhere
else.

This is structural, not a bug in one code path. The staged window is a normal
Wayland client on a normal workspace; nothing marks it "synthetic input only".

### Workaround used

Drive the application through its own IPC instead of synthesising keys. herdr
has a socket API, so creating a second workspace/tab needed no `wtype` at all.
The second verification pass injected zero keystrokes and had no interference.

### Fix, if wanted

Options, roughly in increasing order of effort:

1. Document it: make `screen-verify launch` return a `warning` whenever a
   session is about to take focus, and have the skill prefer app-native IPC over
   key injection. Cheapest, no isolation gained.
2. Send keys to the client directly rather than through the seat -- e.g. a
   virtual-keyboard protocol bound to the staged surface, so focus never moves.
   Needs per-compositor support and does not work for layer surfaces that grab.
3. Run test surfaces on a **separate compositor instance** (nested Hyprland or a
   headless one on its own Wayland socket) with its own seat. Real isolation,
   and it also fixes the dimming problem below, but it is a much larger change
   and loses fidelity to the real desktop.

Note the existing caveat in the skill already says isolation is not guaranteed
and to check the launch result's `warning` field -- that warning does not
currently cover keyboard capture.

## `screen-verify preview hypr-keyword` cannot snapshot numeric Hyprland options

**Status:** open. Found 2026-07-29; blocks accurate colour measurement.

### Symptom

`screen-verify preview hypr-keyword --keyword decoration:inactive_opacity ...`
fails with `Unable to snapshot the Hyprland keyword`. Every numeric option is
affected; string-valued ones work.

### Cause

`pkgs/screen-verify/screen_verify_lib/preview.py:92-97`:

```python
option = run_json(["hyprctl", "getoption", args.keyword, "-j"])
original = option.get("custom")
if not isinstance(original, str):
    raise ScreenError("Unable to snapshot the Hyprland keyword")
```

`hyprctl getoption -j` returns a different key per value type. Verified on this
host:

```
$ hyprctl getoption decoration:inactive_opacity -j
{"option": "decoration:inactive_opacity", "float": 0.700000, "set": true }

$ hyprctl getoption general:col.active_border -j
{"option": "general:col.active_border", "custom": "ff056608 0deg", "set": true }
```

So `custom` exists only for string/custom options. Floats emit `float`, and
integers/bools emit `int` -- none of which the snapshot path looks at.

### Why it matters

Hyprland dims unfocused windows to `inactive_opacity` (0.7 here). Any capture of
a window that is not focused therefore reports every colour at 0.7x -- during the
herdr work a measured `#347D36` turned out to be `#4AB34D x 0.7`. Defeating the
dimming is a prerequisite for trustworthy contrast measurement, and it is
precisely the option that cannot be previewed. The workaround was a manual
`hyprctl keyword` plus a hand-rolled dead-man's switch to restore 0.7, which is
exactly the unsafe pattern `preview` exists to prevent.

### Fix

Read whichever key is present and round-trip it as a string:

```python
option = run_json(["hyprctl", "getoption", args.keyword, "-j"])
for key in ("custom", "str", "float", "int"):
    if key in option:
        original = option[key]
        break
else:
    raise ScreenError("Unable to snapshot the Hyprland keyword")
original = str(original)
```

Check the restore path in `screen-verify end` too -- it replays `original`
through `hyprctl keyword`, which accepts the numeric text form, but the
`isinstance(..., str)` guard may repeat there.

Consider also having the capture path either focus the target window or
temporarily set `inactive_opacity` to 1.0 for the duration of a session, so
colour measurement is correct by default rather than by remembering to.
