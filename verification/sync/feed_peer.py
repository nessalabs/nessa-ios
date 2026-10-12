"""Scripted, loopback-only peer for native subscription lifecycle experiments."""
import asyncio
import json
import sys
import time
from pathlib import Path
import websockets

A = "00000000-0000-4000-8000-000000000001"
B = "00000000-0000-4000-8000-000000000002"
C = "00000000-0000-4000-8000-000000000003"

async def peer(socket):
    mode = ""
    live = {}
    jobs = set()
    await socket.send(json.dumps({"type": "event", "event": "session.challenge", "payload": {
        "minVersion": 1, "maxVersion": 1, "nonce": "fixture", "expiresAt": time.time() + 60}}))
    async def reply(request, payload=None, code=None):
        frame = {"type": "res", "id": request["id"], "ok": code is None}
        if code: frame["error"] = {"code": code, "message": code}
        else: frame["payload"] = payload or {}
        await socket.send(json.dumps(frame))
    async def event(name, payload):
        await socket.send(json.dumps({"type": "event", "event": name, "payload": payload}))
    async def registered(request, conversation):
        if conversation == A:
            if mode == "lost": return
            await asyncio.sleep(0.5)
        if any(target is not None for target in live.values()):
            await reply(request, code="subscription_duplicate")
            return
        subscription = "view-" + conversation
        live[subscription] = conversation
        await reply(request, {"subscriptionId": subscription})
        if mode == "missing": return
        target = B if mode == "foreign" else conversation
        await event("conversation.view", {"subscriptionId": subscription,
            "cursor": {"incarnation": "fixture", "position": "1"},
            "view": {"conversationId": target, "messages": [], "permissions": [], "truncated": False}})
    async def stopped(request):
        subscription = request["params"]["subscriptionId"]
        if mode == "active": await asyncio.sleep(0.2)
        if subscription in live:
            del live[subscription]
            await reply(request)
        else: await reply(request, code="unknown_subscription")
    try:
        async for raw in socket:
            request = json.loads(raw)
            method, params = request["method"], request["params"]
            if method == "session.authenticate":
                if params["credential"] != "fixture-only":
                    await reply(request, code="unauthorized")
                    return
                mode = params["surface"]["instance"]
                await reply(request, {"version": 1})
            elif method == "conversation.subscribeList":
                live["inbox"] = None
                await reply(request, {"subscriptionId": "inbox"})
                await event("conversation.listed", {"subscriptionId": "inbox", "list": {"conversations": [], "complete": True}})
            elif method == "conversation.subscribe":
                job = asyncio.create_task(registered(request, params["conversationId"]))
                jobs.add(job)
                job.add_done_callback(jobs.discard)
            elif method == "conversation.unsubscribe":
                job = asyncio.create_task(stopped(request))
                jobs.add(job)
                job.add_done_callback(jobs.discard)
            else: await reply(request, code="invalid_request")
    finally:
        for job in jobs: job.cancel()
        await asyncio.gather(*jobs, return_exceptions=True)

async def main():
    async with websockets.serve(peer, "127.0.0.1", 0) as server:
        port = server.sockets[0].getsockname()[1]
        Path(sys.argv[1]).write_text(str(port))
        print(json.dumps({"ready": port}), flush=True)
        await asyncio.Future()

asyncio.run(main())
