"""Loopback-only real WebSocket pairing contract and admission-race fixture."""
import asyncio
import json
import sys
import time
import uuid
from pathlib import Path
import websockets

ROOT = Path(sys.argv[1]).parent

def status():
    return {'invitationId': list(range(16)), 'consentId': list(range(16,32)), 'generation': 2**64-1,
            'class': 'gateway-conversation-read', 'grant': {'action': 'conversation.read', 'resource': {'organizationId': 'org', 'id': 'gateway'}},
            'createdAtMs': 2**53+1, 'expiresAtMs': 2**64-1, 'phase': 'terminal', 'claimedDeviceKey': list(range(32)),
            'credentialId': 'device-credential', 'receiver': {'receiverId': 'receiver', 'accessEpoch': 2**64-1},
            'terminal': {'cause': 'cancelled', 'initiator': {'kind': 'device', 'deviceKey': list(range(32))}}, 'cleanupPending': True}

async def peer(socket):
    nonce = str(uuid.uuid4())
    mode = ''
    await socket.send(json.dumps({'type':'event','event':'session.challenge','payload':{'minVersion':1,'maxVersion':1,'nonce':nonce,'expiresAt':time.time()+60}}))
    async for raw in socket:
        req = json.loads(raw)
        method, params = req['method'], req['params']
        response = {'type': 'res', 'id': req['id'], 'ok': True}
        if method == 'session.authenticate':
            assert params['nonce'] == nonce and params['credential'] == 'fixture-only'
            mode = params['surface']['instance']
            response['payload'] = {'version':1,'gatewayId':'gateway','principalId':'owner-'+mode,'organizationId':'org',
                                   'membershipId':'membership','credentialId':'credential','audienceId':'audience',
                                   'expiresAt':None,'grants':[],'methods':['pairing.create','pairing.status','pairing.approve','pairing.cancel','pairing.pending']}
        elif method.startswith('pairing.'):
            ROOT.joinpath(mode+'.request').write_text(json.dumps({'method':method,'params':params}))
            expected = {'pairing.create': {'enrollee':'device'}, 'pairing.status': {'invitationId':list(range(16))},
                        'pairing.approve': {'invitationId':list(range(16)), 'deviceKey':list(range(32))},
                        'pairing.cancel': {'invitationId':list(range(16))}, 'pairing.pending': {}}
            assert params == expected[method], (method, params)
            if mode.startswith('delay-'):
                for _ in range(1000):
                    if ROOT.joinpath(mode+'.release').exists(): break
                    await asyncio.sleep(.01)
                else: raise TimeoutError(mode)
            payload = status()
            if method == 'pairing.create': payload = {'code':'ABCD-EFGH','status':payload}
            if method == 'pairing.approve': payload = {'status':payload,'activationStopped':'retryable'}
            if method == 'pairing.pending': payload = {'items':[payload]}
            response['payload'] = payload
            if mode.startswith('error-'):
                response.pop('payload'); response['ok'] = False
                response['error'] = {'code':mode[6:],'message':'diagnostic which says active and revoked but is not authority','details':{'ordinal':2**64-1}}
            elif mode == 'bad-ok': response['ok'] = 1
            elif mode == 'missing-ok': response.pop('ok')
            elif mode == 'missing-id': response.pop('id')
            elif mode == 'empty-id': response['id'] = ''
            elif mode == 'wrong-kind': response['type'] = 7
            elif mode == 'missing-payload': response.pop('payload')
            elif mode == 'contradiction': response['error'] = {'code':'forbidden','message':''}
            elif mode == 'missing-code':
                response.pop('payload'); response['ok'] = False; response['error'] = {'message':'forbidden'}
            elif mode == 'null-option': response['payload'] = dict(status(), receiver=None)
            elif mode == 'zero-generation': response['payload'] = dict(status(), generation=0)
            elif mode == 'overflow': response['payload'] = dict(status(), generation=2**64)
            elif mode == 'fraction': response['payload'] = dict(status(), generation=1.5)
            elif mode == 'bool-byte': response['payload'] = dict(status(), invitationId=[True]*16)
        else: raise AssertionError(method)
        if mode == 'malformed-json' and method.startswith('pairing.'):
            await socket.send('{')
        else:
            await socket.send(json.dumps(response))

async def main():
    async with websockets.serve(peer, '127.0.0.1', 0) as server:
        Path(sys.argv[1]).write_text(str(server.sockets[0].getsockname()[1]))
        await asyncio.Future()

asyncio.run(main())
