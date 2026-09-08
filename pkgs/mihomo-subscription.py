"""Import short-lived subscription URLs without replacing the system config."""

import json
import os
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

import yaml

STATE = Path(os.environ["STATE_DIRECTORY"])
CACHE = STATE / "ssrdog.yaml"
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
LOCK = Lock()
MAX_BYTES = 4 * 1024 * 1024


def refresh():
    request = urllib.request.Request(
        "http://127.0.0.1:9090/providers/proxies/subscription", method="PUT"
    )
    with HTTP.open(request, timeout=15):
        pass


def import_subscription(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Paste the HTTPS subscription link copied from your provider.")
    request = urllib.request.Request(url, headers={"User-Agent": "Clash.Meta"})
    try:
        with HTTP.open(request, timeout=30) as response:
            data = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as error:
        if error.code == 403:
            raise ValueError("The provider rejected this link. Copy a fresh link and try again.") from None
        raise ValueError(f"The provider returned HTTP {error.code}.") from None
    except (urllib.error.URLError, TimeoutError):
        raise ValueError("Could not reach the provider. Your saved subscription is unchanged.") from None
    if len(data) > MAX_BYTES:
        raise ValueError("The subscription response is too large.")
    try:
        document = yaml.safe_load(data)
    except yaml.YAMLError:
        raise ValueError("The provider did not return a Clash subscription.") from None
    proxies = document.get("proxies") if isinstance(document, dict) else None
    if not isinstance(proxies, list) or not proxies:
        raise ValueError("The subscription contains no proxy nodes.")
    if any(not isinstance(p, dict) or not p.get("name") or not p.get("type") for p in proxies):
        raise ValueError("The subscription contains an invalid proxy node.")
    # Only proxy definitions cross into the system; provider routing and ports do not.
    payload = yaml.safe_dump({"proxies": proxies}, allow_unicode=True, sort_keys=False)
    with tempfile.TemporaryDirectory(dir=STATE) as directory:
        config = Path(directory) / "config.yaml"
        config.write_text(payload)
        result = subprocess.run(
            [os.environ["MIHOMO"], "-t", "-d", directory, "-f", str(config)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20,
        )
        if result.returncode:
            raise ValueError("Mihomo rejected the subscription. Your saved nodes are unchanged.")
        previous = CACHE.read_bytes() if CACHE.exists() else None
        os.replace(config, CACHE)
        try:
            refresh()
        except Exception:
            if previous is not None:
                config.write_bytes(previous)
                os.replace(config, CACHE)
                refresh()
            else:
                CACHE.unlink(missing_ok=True)
            raise ValueError("Could not refresh Mihomo; the previous subscription was restored.") from None
    return len(proxies)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        # Request URLs and subscription tokens must never enter the journal.
        pass

    def allowed_origin(self):
        origin = self.headers.get("Origin", "")
        parsed = urllib.parse.urlsplit(origin)
        return origin if parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"} else None

    def reply(self, status, data):
        self.send_response(status)
        origin = self.allowed_origin()
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        if not self.allowed_origin():
            return self.reply(403, {"error": "Open the dashboard on this machine."})
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", self.allowed_origin())
        self.send_header("Access-Control-Allow-Methods", "POST")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        if self.path != "/subscription" or not self.allowed_origin():
            return self.reply(403, {"error": "Open the dashboard on this machine."})
        if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            return self.reply(415, {"error": "Expected JSON."})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 16384:
                raise ValueError("Invalid request size.")
            request = json.loads(self.rfile.read(length))
            url = request.get("url")
            if not isinstance(url, str):
                raise ValueError("Paste a fresh subscription URL.")
            with LOCK:
                count = import_subscription(url.strip())
            self.reply(200, {"count": count})
        except (ValueError, json.JSONDecodeError) as error:
            self.reply(400, {"error": str(error)})
        except Exception:
            self.reply(500, {"error": "Import failed. Your system configuration is unchanged."})


if __name__ == "__main__":
    os.umask(0o077)
    ThreadingHTTPServer(("127.0.0.1", 9091), Handler).serve_forever()
