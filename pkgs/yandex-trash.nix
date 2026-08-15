{
  writers,
  yadisk,
}:

# Recovery tool for the Yandex Disk trash.
#
# The trash is what covers deletions in the window restic's snapshot interval
# cannot reach: the sync daemon propagates a delete to the cloud within
# seconds, and the server keeps the file. rclone is no help here -- its yandex
# backend implements only CleanUp(), which empties the trash rather than
# reading it -- so this talks to the REST API directly.
#
# There is deliberately no purge subcommand. This tool exists to read the
# safety net; it should not be able to destroy it.
writers.writePython3Bin "yandex-trash"
  {
    libraries = [ yadisk ];
    flakeIgnore = [
      "E501" # long lines in help text read better unwrapped
      "E402"
    ];
  }
  ''
    """List and restore files from the Yandex Disk trash."""

    import argparse
    import os
    import sys
    import time
    from pathlib import Path

    import yadisk

    DEFAULT_TOKEN_FILE = "~/.nixos-config/secrets/yandex-token"


    def read_token():
        token = os.environ.get("YANDEX_DISK_TOKEN")
        if token:
            return token.strip()
        path = Path(
            os.environ.get("YANDEX_DISK_TOKEN_FILE", DEFAULT_TOKEN_FILE)
        ).expanduser()
        if not path.is_file():
            sys.exit(
                f"no token found.\n"
                f"  set YANDEX_DISK_TOKEN, or place one at {path}\n"
                f"  mint one at https://oauth.yandex.com/ (scope: cloud_api:disk.read, cloud_api:disk.write)"
            )
        return path.read_text().strip()


    def human(size):
        if size is None:
            return "-"
        value = float(size)
        for unit in ("B", "K", "M", "G", "T"):
            if abs(value) < 1024:
                return f"{value:.0f}{unit}"
            value /= 1024
        return f"{value:.0f}P"


    def cmd_list(client, args):
        rows = []

        def walk(path, depth):
            for item in client.trash_listdir(path):
                rows.append(item)
                if depth > 0 and getattr(item, "type", None) == "dir":
                    walk(item.path, depth - 1)

        walk(args.path, args.depth)

        if not rows:
            print("trash is empty")
            return

        rows.sort(key=lambda i: getattr(i, "deleted", None) or "", reverse=True)
        for item in rows:
            deleted = getattr(item, "deleted", None)
            when = deleted.strftime("%Y-%m-%d %H:%M") if deleted else "-"
            kind = "d" if getattr(item, "type", None) == "dir" else "f"
            # origin_path is where it was deleted from -- far more useful than
            # the trash: path you have to pass back in to restore it.
            origin = getattr(item, "origin_path", None) or ""
            print(f"{when}  {kind}  {human(getattr(item, 'size', None)):>6}  {item.path}")
            if origin:
                print(f"{' ' * 32}was: {origin}")


    def cmd_restore(client, args):
        result = client.restore_trash(args.path, dst_path=args.to)

        get_status = getattr(result, "get_status", None)
        if get_status is None:
            # 201 Created -- restore completed synchronously.
            print(f"restored: {getattr(result, 'path', None) or args.path}")
            return

        # 202 Accepted -- Yandex is doing it in the background. Restoring a
        # large resource genuinely takes a while, so poll rather than assume.
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            status = get_status()
            if status == "success":
                print(f"restored: {args.to or args.path}")
                return
            if status == "failed":
                sys.exit("restore failed -- check the Yandex web UI")
            time.sleep(2)

        sys.exit(
            f"still in progress after {args.timeout}s; it may yet succeed -- check the web UI"
        )


    def main():
        parser = argparse.ArgumentParser(
            description="List and restore files from the Yandex Disk trash.",
            epilog="No purge subcommand by design: this reads the safety net, it does not empty it.",
        )
        sub = parser.add_subparsers(dest="command", required=True)

        p_list = sub.add_parser("list", help="list trash contents, newest deletion first")
        p_list.add_argument("path", nargs="?", default="/", help="trash path (default: /)")
        p_list.add_argument(
            "--depth", type=int, default=0, help="descend N levels into trashed directories"
        )
        p_list.set_defaults(func=cmd_list)

        p_restore = sub.add_parser("restore", help="restore a resource out of the trash")
        p_restore.add_argument("path", help="trash path, as shown by 'list'")
        p_restore.add_argument(
            "--to",
            metavar="DST",
            help="restore elsewhere instead of the original location; useful for something large you want to inspect before it lands back in the synced tree",
        )
        p_restore.add_argument(
            "--timeout", type=int, default=300, help="seconds to wait on an async restore"
        )
        p_restore.set_defaults(func=cmd_restore)

        args = parser.parse_args()

        with yadisk.Client(token=read_token()) as client:
            if not client.check_token():
                sys.exit("token rejected by Yandex -- it may have expired")
            args.func(client, args)


    if __name__ == "__main__":
        main()
  ''
