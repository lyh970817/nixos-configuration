"""Adapt the dashboard's remote-config action to the local subscription importer."""

from pathlib import Path
import sys

root = Path(sys.argv[1])
old = "let n=await(await H.get(e)).text();await t.put(`configs`,{searchParams:{force:!0},json:{path:``,payload:n}})"
new = """let u=new URL(subscriptionEndpoint());u.port=String(Number(u.port||9090)+1);u.pathname='/subscription';u.search='';u.hash='';let r=await fetch(u,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({url:e})});let d=await r.json();if(!r.ok)throw new Error(d.error||'Subscription import failed');window.alert('Subscription imported. Your proxy groups and routing are preserved.')"""
matches = 0
for path in root.glob("_nuxt/*.js"):
    text = path.read_text()
    if old in text:
        matches += text.count(old)
        if text.count("function X(){") != 1:
            raise SystemExit("Dashboard endpoint accessor changed; update the patch.")
        text = text.replace("function X(){", "function subscriptionEndpoint(){return n().currentEndpoint.url}function X(){")
        text = text.replace(old, new)
        text = text.replace(
            "throw console.error(`Failed to fetch remote config:`,e),e",
            "throw window.alert(e.message||'Subscription import failed'),e",
        )
    text = text.replace("Fetch Remote Config", "Import Subscription")
    text = text.replace("Enter config file URL", "Paste a freshly copied subscription URL")
    text = text.replace("拉取远程配置", "导入订阅")
    text = text.replace("输入配置文件 URL", "粘贴新复制的订阅链接")
    path.write_text(text)
if matches != 1:
    raise SystemExit(f"Expected one dashboard import action, found {matches}; update the patch.")
