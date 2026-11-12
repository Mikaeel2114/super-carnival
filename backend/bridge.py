"""Private Windows helper. Flutter owns the UI; this process owns capture and consent IPC."""
import json, sys, threading, uuid, time
from server import State, serve, private_ipv4
state = None
server = None
pending = {}
lock = threading.Lock()
output_lock = threading.Lock()
def emit(event):
    with output_lock:
        print(json.dumps(event), flush=True)
def poll():
    while state and state.running:
        try: req = state.requests.get(timeout=.5)
        except Exception: continue
        id = uuid.uuid4().hex
        with lock: pending[id] = req
        emit({'type':'request','id':id,'ip':req['ip']})
def stop():
    global state, server
    if state:
        state.stop()
        with lock:
            for r in pending.values(): r['event'].set()
            pending.clear()
        server.shutdown(); server.server_close(); state = None; server = None
try:
    for line in sys.stdin:
        try:
            data=json.loads(line)
            action=data.get('action')
            if action=='start':
                if state: raise ValueError('Already sharing')
                address=data['ip']; port=int(data['port'])
                if not private_ipv4(address) or address.startswith('127.') or not 1024<=port<=65535: raise ValueError('Use your private Wi-Fi IPv4 address and port 1024–65535')
                state=State(address,port)
                try: server=serve(state)
                except Exception:
                    state=None
                    raise
                threading.Thread(target=poll,daemon=True).start()
                emit({'type':'started','code':state.code,'ip':address,'port':port})
            elif action=='decision':
                with lock: req=pending.pop(str(data.get('id','')),None)
                if req:
                    req['accepted']=bool(data.get('allow')) and time.time()<=req['deadline']
                    req['event'].set()
            elif action=='stop':
                stop(); emit({'type':'stopped'})
        except Exception as e: emit({'type':'error','message':str(e)})
finally: stop()
