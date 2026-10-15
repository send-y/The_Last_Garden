"""Exercise the actual stdio server against isolated headless and graphical Godot."""
import argparse
import base64
import hashlib
import json
import pathlib
import subprocess
import sys
import time
import uuid
from server import Client

REPO = pathlib.Path(__file__).resolve().parents[2]
GODOT = "D:/Godot_v4.7-stable_mono_win64/Godot_v4.7-stable_mono_win64_console.exe"
SAVE = pathlib.Path.home()/"AppData/Roaming/Godot/app_userdata/The Last Garden/first_night_save.json"

def hashes():
    return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None for p in [SAVE,pathlib.Path(str(SAVE)+'.bak')]}

def check(out, graphical, no_render=False):
    mode = out/('suspended-render' if no_render else 'graphic' if graphical else 'headless'); mode.mkdir()
    ipc = mode/'ipc'; log = mode/'game.log'
    command = [GODOT,'--path',str(REPO/'game'),'--max-fps','60']
    command += ['--rendering-method','gl_compatibility'] if graphical else ['--headless']
    command += ['res://tests/garden_bridge_host.tscn','--','--test-save-path='+str(mode/'session.json'),'--garden-bridge-dir='+str(ipc)]
    if no_render: command.append('--bridge-test-no-render')
    with log.open('wb') as stream:
        game = subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT)
        server = None
        try:
            deadline = time.monotonic()+20
            while time.monotonic()<deadline:
                if game.poll() is not None: raise AssertionError(log.read_text(encoding='utf-8'))
                if 'BRIDGE_HOST_READY' in log.read_text(encoding='utf-8',errors='replace'): break
                time.sleep(.05)
            else: raise AssertionError('Host did not become ready: '+log.read_text(encoding='utf-8'))
            client = Client(ipc)
            assert len(client.sessions())==1
            server = subprocess.Popen([sys.executable,str(REPO/'tools/garden_bridge/server.py'),'--root',str(ipc)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
            counter = 0
            def request(method, params=None):
                nonlocal counter
                counter += 1
                server.stdin.write(json.dumps({'jsonrpc':'2.0','id':counter,'method':method,'params':params or {}})+'\n'); server.stdin.flush()
                reply = json.loads(server.stdout.readline())
                assert reply['id']==counter, reply
                return reply['result']
            assert request('initialize',{'protocolVersion':'2025-06-18'})['protocolVersion']=='2025-06-18'
            server.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n'); server.stdin.flush()
            assert len(request('tools/list')['tools'])==5
            def call(name, args=None):
                response = request('tools/call',{'name':name,'arguments':args or {}})
                assert not response.get('isError'), response
                return json.loads(response['content'][0]['text'])
            first = call('get_state'); assert first['paused']
            tree = call('inspect_tree',{'root':'/root/BridgeHost/Game/Hud/HudRoot/StoragePanel','max_depth':12})
            assert any(n['path'].endswith('/InventoryGrid') and not n['clipped'] for n in tree['nodes'])
            errors = call('get_errors')
            assert 'GARDEN_BRIDGE_TEST_MARKER' in json.dumps(errors)
            invalid = request('tools/call',{'name':'execute_code','arguments':{}}); assert invalid['isError']
            # Bypass the Python allowlist to verify runtime rejects arbitrary commands too.
            folder = client.resolve(''); request_id = uuid.uuid4().hex
            (folder/'requests'/f'{request_id}.json').write_text(json.dumps({'id':request_id,'method':'execute_code','params':{}}))
            deadline = time.monotonic()+3; answer = folder/'responses'/f'{request_id}.json'
            while not answer.exists() and time.monotonic()<deadline: time.sleep(.03)
            assert 'error' in json.loads(answer.read_text())
            malformed_id = uuid.uuid4().hex
            (folder/'requests'/f'{malformed_id}.json').write_text(json.dumps({'id':malformed_id,'method':'get_errors','params':{'limit':{}}}))
            malformed_answer = folder/'responses'/f'{malformed_id}.json'
            deadline = time.monotonic()+3
            while not malformed_answer.exists() and time.monotonic()<deadline: time.sleep(.03)
            assert malformed_answer.exists(), 'Malformed IPC blocked diagnostics instead of returning an error'
            assert 'error' in json.loads(malformed_answer.read_text())
            assert call('get_state')['paused'], 'Valid request after malformed IPC failed'
            capture = request('tools/call',{'name':'capture_frame','arguments':{}})
            if graphical and not no_render:
                assert not capture.get('isError'), capture
                data = json.loads(capture['content'][0]['text'])
                assert base64.b64decode(capture['content'][1]['data']).startswith(b'\x89PNG')
                snapshot = json.loads(pathlib.Path(data['snapshot_path']).read_text(encoding='utf-8'))
                assert snapshot['frame_id']==data['frame_id']==snapshot['state']['frame_id']==snapshot['tree']['frame_id']
                (mode/'capture-result.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
            else:
                assert capture['isError'] and ('render' in capture['content'][0]['text'].lower() if no_render else 'headless' in capture['content'][0]['text'])
            last = call('get_state')
            first.pop('frame_id'); last.pop('frame_id')
            assert first==last, 'Reading diagnostics changed simulation'
            (mode/'facts.json').write_text(json.dumps({'state':last,'tree':tree,'errors':errors},indent=2),encoding='utf-8')
            server.stdin.close(); assert server.wait(timeout=5)==0
            assert game.wait(timeout=20)==0
            assert client.sessions()==[]
            assert 'ERROR:' not in log.read_text(encoding='utf-8')
            assert 'BRIDGE_READ_ONLY_PASS' in log.read_text(encoding='utf-8')
            print(mode.name+': PASS',flush=True)
        finally:
            if server and server.poll() is None: server.kill(); server.wait()
            if game.poll() is None: game.kill(); game.wait()

if __name__=='__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('run_id'); args = parser.parse_args()
    if pathlib.Path(args.run_id).name!=args.run_id: parser.error('Invalid run name')
    out = REPO/'artifacts/garden-bridge-2026-10-15'/args.run_id; out.mkdir(parents=True,exist_ok=False)
    before = hashes(); passed = False
    try:
        check(out,False); check(out,True); check(out,True,True); passed = True
    finally:
        after = hashes()
        (out/'result.json').write_text(json.dumps({'passed':passed,'save_before':before,'save_after':after},indent=2))
        assert before==after, 'Ordinary save changed'
