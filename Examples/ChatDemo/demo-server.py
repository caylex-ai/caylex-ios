#!/usr/bin/env python3
"""Local integration fixture; no AI calls or production credentials."""
import argparse
import hmac
import ipaddress
import json
import pathlib
import urllib.request
import urllib.error
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

lock = threading.RLock()
sessions = {}
approvals = {}
credentials_file = None
device_access_token = None

def validate_bind_address(host, access_token):
    if not ipaddress.ip_address(host).is_loopback and not access_token:
        raise ValueError('A non-loopback listener requires --access-token-file')

def mint_live_token():
    if credentials_file is None:
        raise ValueError('No live credentials file configured')
    config = json.loads(credentials_file.read_text())
    allowed = ['https://api.caylex.ai/api/v1/widget/mint-token', 'https://api.caylex.dev/api/v1/widget/mint-token']
    if config['mintURL'] not in allowed:
        raise ValueError('Unsupported token minting endpoint')
    request = urllib.request.Request(config['mintURL'], method='POST',
        data=json.dumps({'caylex_api_key': config['caylexApiKey'], 'user_email': config['userEmail']}).encode(),
        headers={'Authorization': 'Bearer ' + config['platformToken'], 'Content-Type': 'application/json',
                 'User-Agent': 'Caylex-iOS-Integration-Test/0.1'})
    with urllib.request.urlopen(request, timeout=30) as response:
        token = json.load(response)['token']
    return {'apiBaseUrl': config['apiBaseURL'], 'widgetToken': token, 'userName': config.get('userName', 'Isaac')}


def now():
    return datetime.now(timezone.utc).isoformat()

def create_session(sid, name='Demo chat'):
    sessions[sid] = dict(session_id=sid, session_name=name, status='active', created_at=now(),
                         last_message_at=now(), is_playground=False, servers_available=[],
                         navigator_instance_id=None, project_id=None, model_name='demo',
                         navigator_name='Demo agent', message_count=0, events=[], pending_approval=None)
    return sessions[sid]

def event(sid, kind, **fields):
    with lock:
        session = sessions[sid]
        value = dict(type=kind, event_id=str(uuid.uuid4()), message_id=str(uuid.uuid4()),
                     sequence_number=len(session['events']) + 1, timestamp=now(), **fields)
        session['events'].append(value)
        session['message_count'] += 1
        session['last_message_at'] = now()
        return value

create_session('saved-demo', 'Saved conversation')
event('saved-demo', 'user_message', text='What did we discuss last time?')
event('saved-demo', 'assistant_message', text='This is a saved conversation restored through the native Swift controller. Your next message stays in this session.')

class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def json(self, payload, status=200):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if 'application/json' in self.headers.get('Content-Type', ''):
            return json.loads(raw or '{}')
        return raw

    def authorized(self):
        if self.headers.get('Authorization') != 'Bearer demo-token':
            self.json({'detail': 'Demo token expired'}, 401)
            return False
        return True

    def do_GET(self):
        if self.path in ['/demo/config', '/demo/token']:
            if device_access_token and not hmac.compare_digest(
                    self.headers.get('Authorization', '').encode(), ('Bearer ' + device_access_token).encode()):
                self.json({'detail': 'Device pairing key required'}, 403); return
            if self.headers.get('X-Caylex-Demo') != '1':
                self.json({'detail': 'Native demo request header required'}, 403); return
            try:
                self.json(mint_live_token())
            except urllib.error.HTTPError as error:
                self.json({'detail': 'Token minting failed', 'status': error.code}, 502)
            except Exception:
                self.json({'detail': 'No valid live credentials configured'}, 503)
            return
        if not self.authorized(): return
        parsed = urlparse(self.path)
        route = parsed.path.removeprefix('/api/').strip('/')
        if route == 'sessions':
            with lock:
                result = [{k: v for k, v in s.items() if k not in ('events', 'pending_approval')} for s in sessions.values()]
            self.json({'sessions': result, 'count': len(result)})
        elif route == 'background-approvals': self.json({'approvals': [], 'count': 0})
        elif route == 'background-tasks': self.json({'tasks': [], 'count': 0, 'attention_count': 0})
        elif route.endswith('/events'):
            sid = route.split('/')[1]
            session = sessions.get(sid)
            if not session: self.json({'detail': 'Unknown session'}, 404); return
            after = int(parse_qs(parsed.query).get('after_sequence', ['0'])[0])
            self.json({'session_id': sid, 'events': [e for e in session['events'] if e['sequence_number'] > after],
                       'pending_approval': session['pending_approval']})
        elif route.endswith('/resume-status'):
            self.json({'resumable': False, 'reason': 'completed'})
        else: self.json({'detail': 'Demo route unavailable'}, 404)

    def do_POST(self):
        body = self.body()
        if not self.authorized(): return
        route = urlparse(self.path).path.removeprefix('/api/').strip('/')
        if route == 'init':
            sid = 'demo-' + uuid.uuid4().hex[:8]
            create_session(sid, body.get('session_name', 'Chat'))
            self.json({'session_id': sid, 'ready': True, 'servers': [], 'auth_link': None})
        elif route.endswith('/approve'):
            sid = route.split('/')[1]
            approvals[sid] = body.get('decisions', [])
            self.json({'status': 'ok', 'trusts_granted': []})
        elif route == 'chat/stream': self.chat(body)
        elif route.endswith('/name'):
            sessions[route.split('/')[1]]['session_name'] = body.get('session_name', 'Chat')
            self.json({'updated': True})
        elif route == 'files/parse':
            self.json({'filename': 'attachment.txt', 'file_type': 'text/plain', 'markdown': 'Demo attachment parsed successfully.'})
        elif route == 'transcriptions': self.json({'text': 'Demo microphone transcription.'})
        elif route == 'voice/realtime/session':
            self.json({'detail': 'Live voice needs a real Caylex backend; the local fixture tests chat only.'}, 503)
        else: self.json({'detail': 'Demo route unavailable'}, 404)

    def do_PATCH(self): self.do_POST()

    def do_DELETE(self):
        if not self.authorized(): return
        sid = urlparse(self.path).path.rstrip('/').split('/')[-1]
        sessions.pop(sid, None)
        self.json({'deleted': True})

    def chat(self, body):
        sid, prompt = body['session_id'], body.get('message', '')
        event(sid, 'user_message', text=prompt)
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = True

        def emit(kind, **fields):
            data = 'data: ' + json.dumps(dict(type=kind, **fields)) + '\n\n'
            self.wfile.write(data.encode()); self.wfile.flush()

        try:
            emit('started', session_id=sid)
            if 'approval' in prompt.lower():
                tid, batch = 'demo-tool-' + uuid.uuid4().hex[:6], str(uuid.uuid4())
                approval = dict(approval_id='demo-approval', sub_index=0, tool_name='send_message',
                                server_name='Demo service', server_logo_url=None, tool_impact_level='medium',
                                intent='Send a demo message', tool_params={'message': 'Hello from Caylex'})
                emit('text', content='I can send that message. Please approve the action first. ')
                emit('tool_call', tool_id=tid, name='send_message', input=approval['tool_params'])
                event(sid, 'tool_call', tool_use_id=tid, name='send_message', input=approval['tool_params'])
                sessions[sid]['pending_approval'] = dict(batch_id=batch, tool_id=tid, approvals=[approval])
                emit('tool_approval_required', tool_id=tid, batch_id=batch, approvals=[approval])
                deadline = time.time() + 90
                while sid not in approvals and time.time() < deadline:
                    time.sleep(.25)
                decisions = approvals.pop(sid, [])
                accepted = any(d.get('action') == 'approved' for d in decisions)
                sessions[sid]['pending_approval'] = None
                emit('tool_result', tool_id=tid, content='Demo message sent.' if accepted else 'Demo action declined.', is_error=not accepted)
                event(sid, 'tool_result', tool_use_id=tid, content='Demo action resolved.', is_error=not accepted)
                answer = 'The demo action is complete. Approval traveled from the widget through native HTTP to the backend.' if accepted else 'The demo action was declined.'
            elif 'navigate' in prompt.lower():
                tid = 'navigate-' + uuid.uuid4().hex[:6]
                emit('tool_call', tool_id=tid, name='navigate_page_ui', input={'page_name': 'Reports'})
                emit('tool_result', tool_id=tid, content=json.dumps({'resolved_url': 'https://example.com/reports', 'page_name': 'Reports'}), is_error=False)
                answer = 'I opened Reports through the Swift navigation callback.'
            else:
                answer = 'The iOS widget is working. This reply streams through native HTTP into the existing Caylex chat UI.\n\nYou can **restore a session**, switch themes, or try a tool approval.\n\nThis is a local test response, not a live AI answer.'
            for word in answer.split(' '):
                emit('text', content=word + ' ')
                time.sleep(.035)
            event(sid, 'assistant_message', text=answer)
            emit('done', session_id=sid)
        except (BrokenPipeError, ConnectionResetError): pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials-file', type=pathlib.Path, help='Private local JSON file; never commit credentials')
    parser.add_argument('--host', default='127.0.0.1', help='Bind address; device tests use the Mac Wi-Fi IP')
    parser.add_argument('--access-token-file', type=pathlib.Path, help='Temporary device pairing key; required for non-loopback binding')
    args = parser.parse_args()
    credentials_file = args.credentials_file
    if args.access_token_file:
        device_access_token = args.access_token_file.read_text().strip()
        if len(device_access_token) < 32: parser.error('Use a randomly generated pairing key of at least 32 characters')
    try:
        validate_bind_address(args.host, device_access_token)
    except ValueError as error:
        parser.error(str(error))
    server = ThreadingHTTPServer((args.host, 8765), Handler)
    print(f'Caylex demo backend: http://{args.host}:8765/api/', flush=True)
    server.serve_forever()
