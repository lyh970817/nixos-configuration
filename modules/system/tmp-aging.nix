{ ... }:

# /tmp aging.
#
# /tmp is on the root filesystem here, not tmpfs, so nothing clears it at boot.
# systemd already ships `q /tmp 1777 root root 10d` (tmp.conf) and
# systemd-tmpfiles-clean.timer runs it daily -- but it reclaims essentially
# nothing. Measured on linglong: of 51.9 GiB in /tmp, 19.5 GiB was older than
# 10 days by mtime, while the age key systemd uses by default (atime, btime,
# ctime, mtime for files; atime, btime, mtime for directories, whichever is
# youngest) marked 0.00 GiB stale. Any full-tree read resets atime for every
# file it touches and every readdir resets it for every directory, and /tmp
# here gets walked constantly -- 953k files had their atime refreshed on a
# single day. atime is therefore not a liveness signal on this machine, it is
# noise that permanently pins whatever it touches.
#
# So both rules below key on mtime alone (`mM`: lower case for files, upper
# case for directories). mtime advances only when something is written, which
# is what "still in use" actually means for scratch. ctime was also considered
# and rejected: including it dropped the reclaimable set from 5.72 GiB to
# 1.57 GiB at the same cutoff, because metadata operations during pipeline runs
# refresh it without the data being live.
#
# Two tiers, because Claude Code session scratch has a different lifetime from
# an ordinary mktemp directory.

{
  systemd.tmpfiles.rules = [
    # --- exclusions, first, because the tier 1 rule below recurses ---
    #
    # systemd-tmpfiles removes sockets and FIFOs just like regular files
    # (verified with `systemd-tmpfiles --clean --dry-run`), and a server's
    # socket keeps the mtime it had when it was bound. A tmux server that has
    # been up longer than the tier 1 age would therefore have its socket
    # deleted underneath it, detaching every session and losing every running
    # pane. Same shape for the other long-lived listeners in /tmp.
    "x /tmp/tmux-*"
    "x /tmp/nvim.*"
    "x /tmp/.ydotool_socket"
    "x /tmp/codex-browser-use"

    # Claude Code scratch is excluded from tier 1 and handled by tier 2 below;
    # an `x` on this directory stops the tier 1 walk descending into it without
    # affecting the separate rule rooted inside it.
    "x /tmp/claude-[0-9]*"

    # --- tier 1: ordinary /tmp scratch, 14 days ---
    #
    # Shadows tmp.conf's line for the same path (00-nixos.conf sorts first, so
    # systemd logs "Duplicate line for path /tmp, ignoring" against tmp.conf and
    # uses this one). 14d rather than upstream's nominal 10d: this key actually
    # fires, so the extra margin buys back the safety that switching away from
    # atime gives up, while still bounding ordinary scratch to a fortnight of
    # inflow. Type and mode are copied from upstream's line unchanged.
    "q /tmp 1777 root root mM:14d"

    # --- tier 2: Claude Code per-session scratch, 30 days ---
    #
    # /tmp/claude-<uid>/<project>/<session-uuid>/ is the harness scratchpad
    # root, and agents are told to put every temporary file there, so pipeline
    # work directories land in it -- two finished sessions accounted for 20 GiB.
    # The rule cleans the contents of each project directory, i.e. it reaps
    # whole session directories, leaving the project directories in place.
    #
    # 30 days because sessions are resumable and can idle for a long time, but
    # a live session writes into its scratchpad constantly, so its mtime is
    # never more than minutes old while it is running. A session directory with
    # no write in a month is finished.
    #
    # Caveat: aging cannot see an open file descriptor. A process that appends
    # to nothing for 30 days while holding a scratchpad file open would lose it
    # -- a real shape here, a benchmark script was found still running 13 days
    # after its session went idle. Nothing on this machine has hit 30 days, and
    # a process that needs the guarantee can take a BSD lock on the directory,
    # which systemd-tmpfiles honours (tmpfiles.d(5), "Age"). scripts/
    # prune-scratch.py, used for one-off manual reclaim, does check open fds.
    "e /tmp/claude-[0-9]*/* - - - mM:30d"
  ];
}
