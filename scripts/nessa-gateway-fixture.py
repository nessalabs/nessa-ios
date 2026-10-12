"""Local protocol fixture, never a production gateway. Requires aiohttp."""
import asyncio, json, time, hashlib, uuid
from aiohttp import web

TICKETS = {}
STORED = {}

CONVERSATION = '00000000-0000-4000-8000-000000000001'
async def session(request):
    socket = web.WebSocketResponse()
    await socket.prepare(request)
    await socket.send_str(json.dumps({'type':'event','event':'session.challenge','payload':{'minVersion':1,'maxVersion':1,'nonce':'test-nonce','expiresAt':time.time()+60},'seq':0,'stateVersion':0}))
    async for raw in socket:
        if raw.type != web.WSMsgType.TEXT: continue
        request=json.loads(raw.data)
        assert request['type']=='req'
        method, p = request['method'],request['params']
        result={}
        if method=='session.authenticate':
            assert p['nonce']=='test-nonce' and p['credential']=='fixture'
            assert p['surface']['kind']=='panel' and p['minVersion']==p['maxVersion']==1
            result={'version':1, 'gatewayId':'fixture-gateway', 'principalId':'fixture-owner',
                'organizationId':'fixture-org', 'membershipId':'fixture-membership',
                'credentialId':'fixture-credential', 'audienceId':'fixture-audience',
                'expiresAt':None, 'grants':[], 'methods':[]}
        elif method=='agents.list':
            result={'agents':[{'agent':a,'defaultModel':'test-model'} for a in ['nessa','codex','claude','opencode','research','planner','writer','reviewer','assistant']]}
        elif method=='conversation.list':
            result={'complete':True,'conversations':[{'conversationId':CONVERSATION,'title':'A little help with today','preview':'Let’s make room for what matters.','updatedAtMs':time.time()*1000,'running':False}]}
        elif method=='conversation.create':
            assert p['requestId']
            result={'conversationId':p['conversationId']}
        elif method=='conversation.read':
            result={'conversationId':p['conversationId'],'truncated':False,'messages':[{'executionId':'turn1','userText':'Can you help me plan my day?','status':'completed','parts':[{'offset':0,'kind':'text','text':'Hello ','messageId':'a'},{'offset':1,'kind':'text','text':'there','messageId':'a'},{'offset':2,'kind':'text','text':'Second reply','messageId':'b'}]}], 'permissions':[{'executionId':'turn1','permissionId':'permission1','title':'Read your calendar?','toolName':'calendar.read','argumentsJson':'{"date":"today"}','options':[{'id':'allow-once','label':'Allow once','effect':'allow'},{'id':'deny','label':'Don’t allow','effect':'deny'}]}]}
        elif method=='attachment.begin':
            ticket = uuid.uuid4().hex
            TICKETS[ticket] = p
            result={'requestId':p['requestId'],'state':'upload_required','ticket':ticket,'expiresAtMs':time.time()*1000+60000,'digest':None,'mimeType':None,'size':None}
        elif method=='conversation.send':
            assert p['requestId'] and p['executionId'] and p['files']==[]
            if p['attachments']:
                assert p['text']=='' and len(p['attachments'])==1
                assert p['attachments'][0] == STORED[p['attachments'][0]['digest']]
            else: assert p['text']=='Hello Nessa'
        elif method=='conversation.answer':
            assert p['optionId']=='allow-once' and p['permissionId']=='permission1'
        else: raise AssertionError(method)
        await socket.send_str(json.dumps({'type':'res','id':request['id'],'ok':True,'payload':result}))
    return socket

async def upload(request):
    ticket = request.headers.get('x-nessa-upload-ticket')
    p = TICKETS.pop(ticket, None)
    assert p is not None
    assert not request.headers.get('Cookie') and not request.headers.get('Authorization')
    data = await request.read()
    assert len(data)==p['size'] and request.content_type==p['mimeType']
    assert 'sha256:'+hashlib.sha256(data).hexdigest()==p['digest']
    ref={k:p[k] for k in ['digest','mimeType','size']}
    STORED[p['digest']]=ref
    return web.json_response(ref)

app = web.Application(client_max_size=64*1024*1024)
app.router.add_get('/session',session)
app.router.add_put('/attachments',upload)
web.run_app(app, host='127.0.0.1', port=18742, print=lambda line: print(line, flush=True))
