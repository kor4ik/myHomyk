# Runs inside the HA container: validates every YAML dashboard over the websocket API.
import asyncio
import os
import re
import sys

import aiohttp

TOKEN = os.environ["HA_TOKEN"]
ALLOW = {x for x in os.environ.get("HA_ALLOW_MISSING", "").split(",") if x}
CUSTOM_OK = {"button-card", "grid-layout", "layout-card", "my-slider", "simple-clock-card", "state-switch"}
DOMAINS = (
    "light|switch|sensor|binary_sensor|climate|cover|lock|media_player|remote|weather|group|camera|"
    "person|device_tracker|fan|input_boolean|input_number|input_select|script|scene|automation|water_heater"
)
ENTITY = re.compile(r"\b(?:%s)\.[a-z0-9_]+\b" % DOMAINS)


def leaves(node):
    if isinstance(node, dict):
        for v in node.values():
            yield from leaves(v)
    elif isinstance(node, list):
        for v in node:
            yield from leaves(v)
    elif isinstance(node, str):
        yield node


def dicts(node):
    if isinstance(node, dict):
        yield node
        for v in node.values():
            yield from dicts(v)
    elif isinstance(node, list):
        for v in node:
            yield from dicts(v)


async def main():
    failures = []
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect("http://127.0.0.1:8123/api/websocket") as ws:
            await ws.receive_json()
            await ws.send_json({"type": "auth", "access_token": TOKEN})
            if (await ws.receive_json())["type"] != "auth_ok":
                print("FAIL auth: token rejected")
                return 1
            seq = 0

            async def call(**kw):
                nonlocal seq
                seq += 1
                await ws.send_json({"id": seq, **kw})
                while True:
                    msg = await ws.receive_json()
                    if msg.get("id") == seq:
                        return msg

            states = {s["entity_id"] for s in (await call(type="get_states"))["result"]}
            services = {
                f"{d}.{s}" for d, svc in (await call(type="get_services"))["result"].items() for s in svc
            }
            dashboards = [d["url_path"] for d in (await call(type="lovelace/dashboards/list"))["result"]]
            for path in dashboards:
                msg = await call(type="lovelace/config", url_path=path)
                if not msg.get("success"):
                    failures.append(f"{path}: config failed to load: {msg['error']['message']}")
                    continue
                cfg = msg["result"]
                templates = set(cfg.get("button_card_templates") or {})
                views = cfg.get("views") or []
                for d in dicts(views):
                    t = d.get("type")
                    if isinstance(t, str) and t.startswith("custom:") and t[7:] not in CUSTOM_OK:
                        failures.append(f"{path}: unknown custom type {t}")
                    tpl = d.get("template")
                    if isinstance(tpl, (str, list)) and d.get("type") == "custom:button-card":
                        for name in [tpl] if isinstance(tpl, str) else tpl:
                            if name not in templates:
                                failures.append(f"{path}: missing button-card template {name}")
                refs = {m for s in leaves(views) for m in ENTITY.findall(s)}
                for ref in sorted(refs - states - services - ALLOW):
                    failures.append(f"{path}: entity not found {ref}")
                print(f"checked {path}: {len(views)} views, {len(refs)} entity refs")
    for f in sorted(set(failures)):
        print("FAIL", f)
    return 1 if failures else 0


sys.exit(asyncio.run(main()))
