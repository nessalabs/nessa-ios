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
commands = {}
creation_counts = {}
refused_once = set()

def frozen(params, operation):
    fields = ["conversationId", "requestId", "agent", "model"] if operation == "create" else [
        "conversationId", "requestId", "executionId", "text", "attachments", "files"]
    return {"operation": operation, **{field: params.get(field) for field in fields}}

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
            elif mode.startswith("journal") and method in ("conversation.create", "conversation.send"):
                operation = "create" if method == "conversation.create" else "submit"
                value = frozen(params, operation)
                key = (mode, params["requestId"])
                existing = commands.get(key)
                if mode == "journal-product-refusal-" + operation and mode not in refused_once:
                    refused_once.add(mode)
                    await reply(request, code="model_unavailable" if operation == "create" else "image_input_unsupported")
                    continue
                if mode.endswith("-later-refusal") and existing is not None:
                    await reply(request, code="model_unavailable")
                    continue
                if existing is not None and existing != value:
                    await reply(request, code="conversation_request_conflict")
                    continue
                if existing is None:
                    commands[key] = value
                    if operation == "create":
                        count_key = (mode, params["conversationId"])
                        creation_counts[count_key] = creation_counts.get(count_key, 0) + 1
                    if mode == "journal-lost-" + operation or mode.startswith("journal-product-lost-" + operation):
                        await socket.close()
                        return
                if operation == "create":
                    target = B if mode == "journal-wrong" else params["conversationId"]
                    await reply(request, {"conversationId": target})
                else:
                    await reply(request, {"executionId": params["executionId"], "disposition": "queued"})
            elif mode.startswith("journal") and method == "conversation.receipt":
                value = frozen(params, params["operation"])
                existing = commands.get((mode, params["requestId"]))
                if existing is not None and existing != value:
                    await reply(request, code="conversation_request_conflict")
                    continue
                found = existing is not None and not mode.endswith(("-unknown", "-later-refusal"))
                result = {"found": found, "requestId": B if mode == "journal-wrong" else params["requestId"]}
                if found:
                    result["stage"] = "ready" if params["operation"] == "create" else "settled"
                    if params["operation"] == "submit": result["outcome"] = "dispatched"
                await reply(request, result)
            elif mode.startswith("journal") and method == "conversation.read":
                target = params["conversationId"]
                messages = [{"executionId": value["executionId"], "userText": value["text"], "parts": [], "status": "completed"}
                    for (instance, _), value in commands.items()
                    if instance == mode and value["operation"] == "submit" and value["conversationId"] == target]
                await reply(request, {"conversationId": target, "messages": messages, "permissions": [], "truncated": False,
                    "runtime": {"agent": "creates-" + str(creation_counts.get((mode, target), 0))}})
            elif mode.startswith("journal") and method == "conversation.list":
                await reply(request, {"conversations": [], "complete": True})
            elif mode.startswith("journal") and method == "agents.list":
                await reply(request, {"agents": [{"agent": "fixture", "defaultModel": "text", "models": [
                    {"modelId": "text", "displayName": "Text", "imageInput": False}]}]})
            elif mode.startswith("journal") and method == "attachment.begin":
                # Simulate an already-stored, content-addressed image without an HTTP upload.
                await reply(request, {"state": "stored", "digest": params["digest"],
                    "mimeType": params["mimeType"], "size": params["size"]})
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
