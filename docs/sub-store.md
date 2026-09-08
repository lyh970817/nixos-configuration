# Subscription updates

Open **Sub-Store** from the application launcher on the machine you want to
update. Each machine has its own local instance and subscription state.

1. Copy a fresh subscription URL from SSRDOG.
2. Edit the existing **SSRDOG** subscription in Sub-Store and replace its URL.
   Keep its name and the `Clash.Meta` User-Agent.
3. Click **Preview** while the link is still valid. Check that the expected
   nodes appear, close the preview, then click **Save**.
4. In the stock Mihomo dashboard, open **Proxies → Proxy Providers** and refresh
   **subscription** to apply immediately. Otherwise Mihomo refreshes its local
   Sub-Store provider hourly.

Sub-Store's resource and usage-header caches are set to one year because SSRDOG
links expire after five minutes. A changed URL gets a fresh cache entry. Preview
before saving ensures that a new URL is fetched during its short validity
window. Avoid clearing Sub-Store's resource cache unless you have a fresh link.
Usage figures reflect the saved fetch, rather than live account usage.

Mihomo also keeps its own downloaded provider cache. Its main configuration
contains only the Residential proxy and the subscription-backed groups. Routing
rules stay in `secrets/mihomo-config.yaml`; Residential retains
`dialer-proxy: SSRDOG`, so the selected SSRDOG node carries the connection to the
residential exit.

Both upstream web UIs and the Sub-Store backend are packaged without local source
patches. The local service listens on `127.0.0.1:3001`, stores private data under
`/var/lib/sub-store`, and uses a private backend path from
`secrets/mihomo-cache/sub-store.env`. The launcher supplies that path to the UI.
Do not commit the environment file, subscription URLs, or downloaded nodes.

## Manage the other machine

Use the application launchers **Mihomo — Home Desktop** and **Sub-Store — Home Desktop** on the laptop. On the desktop, use **Mihomo — Laptop** and **Sub-Store — Laptop**. The other machine must be awake and connected to Tailscale.

The launchers start a user service that forwards local ports 19090 (Mihomo) and 13001 (Sub-Store) through Tailscale SSH. It reconnects after interruptions and stops at logout; no public listener or dashboard source modification is needed. Local dashboards retain ports 9090 and 3001, keeping browser settings separate. The Mihomo launcher explicitly selects the peer endpoint, and the Sub-Store launcher reads the peer’s access path over SSH.

Changes in these windows apply to the other machine. Subscription state remains independent on each host. Stop the tunnel with `systemctl --user stop peer-dashboards`.
