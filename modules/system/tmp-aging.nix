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
# So the rule below keys on mtime alone (`mM`: lower case for files, upper
# case for directories). mtime advances only when something is written, which
# is what "still in use" actually means for scratch. ctime was also considered
# and rejected: including it dropped the reclaimable set from 5.72 GiB to
# 1.57 GiB at the same cutoff, because metadata operations during pipeline runs
# refresh it without the data being live.
#
# One rule, plus exclusions. Claude Code session scratch is deliberately NOT
# aged here -- see the note under the exclusion for it.

{
  systemd.tmpfiles.rules = [
    # --- exclusions, first, because the aging rule below recurses ---
    #
    # systemd-tmpfiles removes sockets and FIFOs just like regular files
    # (verified with `systemd-tmpfiles --clean --dry-run`), and a server's
    # socket keeps the mtime it had when it was bound. A tmux server that has
    # been up longer than the aging cutoff would therefore have its socket
    # deleted underneath it, detaching every session and losing every running
    # pane. Same shape for the other long-lived listeners in /tmp. These are
    # load-bearing, not belt-and-braces: /tmp/.ydotool_socket and
    # /tmp/tmux-1000/default were both measured past the 14d line while their
    # servers were running.
    "x /tmp/tmux-*"
    "x /tmp/nvim.*"
    "x /tmp/.ydotool_socket"
    "x /tmp/codex-browser-use"

    # Claude Code per-session scratch is excluded outright and never aged by
    # tmpfiles. Do not "restore" a rule inside this tree -- an earlier revision
    # had `e /tmp/claude-[0-9]*/* - - - mM:30d`, intending to reap whole
    # finished session directories while leaving the project directories in
    # place. tmpfiles.d cannot express that:
    #
    #   * Cleanup is per-file recursive with no depth limit. `e` sets the age
    #     on the matched directories, then every file underneath is judged on
    #     its OWN timestamp; there is no "the directory is young, keep the
    #     subtree" semantics anywhere in tmpfiles.d(5).
    #   * mtime on extracted content is the packager's clock, not a liveness
    #     signal. Unpacked tarballs and conda package trees arrive already
    #     years stale, so a session created this week is full of files that
    #     read as ancient the moment they land.
    #
    # Dry-running the generated config caught exactly that. With the `e` line
    # in, `systemd-tmpfiles --clean --dry-run` proposed 19561 removals under
    # /tmp/claude-1000, spread over 397 session directories -- 13 of which had
    # their own mtime younger than 30 days, i.e. the rule's own cutoff said
    # keep them. Among the casualties: the live session the check was run from,
    # and a 4.87-day-old session losing 13581 entries, mostly unpacked conda
    # package trees under its scratchpad. The session mtimes were fine; the
    # contents were not, and cleanup never consults the former.
    #
    # With the line removed the same dry run proposes 0 removals anywhere under
    # /tmp/claude-1000 -- the `x` below covers the whole tree on its own.
    #
    # Session scratch is reclaimed by scripts/prune-scratch.py instead, which
    # keys on the session directory as a unit, checks /proc for open fds and
    # cwds, and only ever removes hardcoded targets.
    "x /tmp/claude-[0-9]*"

    # --- ordinary /tmp scratch, 14 days ---
    #
    # Shadows tmp.conf's line for the same path (00-nixos.conf sorts first, so
    # systemd logs "Duplicate line for path /tmp, ignoring" against tmp.conf and
    # uses this one). 14d rather than upstream's nominal 10d: this key actually
    # fires, so the extra margin buys back the safety that switching away from
    # atime gives up, while still bounding ordinary scratch to a fortnight of
    # inflow. Type and mode are copied from upstream's line unchanged.
    "q /tmp 1777 root root mM:14d"
  ];
}
