#!/usr/bin/env bash
# Pausa explícita por socket; la restauración sólo toca los sockets del snapshot.
# Sin respuesta de mpv nunca se inventa «playing» ni un éxito.
set -eu
exec python3 - "${XDG_RUNTIME_DIR:?}" "$@" <<'PY'
import glob, json, os, socket, sys
runtime, action = sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else ''
if action not in ('on', 'off', 'status', 'restore'):
    sys.exit('Usage: wallpaper-video-pause.sh on|off|status [--json]|restore <json>')
targets = json.loads(sys.argv[3]) if action == 'restore' else None
if targets is not None and (not isinstance(targets, dict) or any(
        not k.startswith('sumi-mpvpaper-') or not k.endswith('.sock') or '/' in k or type(v) is not bool
        for k, v in targets.items())):
    sys.exit('Invalid wallpaper snapshot')
paths = [os.path.join(runtime, k) for k in targets] if targets is not None else sorted(glob.glob(runtime + '/sumi-mpvpaper-*.sock'))
result, failed = {}, False
for path in paths:
    name = os.path.basename(path)
    cmd = ['get_property', 'pause'] if action == 'status' else ['set_property', 'pause', targets[name] if targets is not None else action == 'on']
    try:
        with socket.socket(socket.AF_UNIX) as sock:
            sock.settimeout(1.5)
            sock.connect(path)
            sock.sendall((json.dumps({'command': cmd, 'request_id': 11}) + '\n').encode())
            pending, reply = b'', None
            while reply is None:
                chunk = sock.recv(4096)
                if not chunk: raise OSError('No reply from mpv')
                pending += chunk
                if len(pending) > 65536: raise OSError('mpv reply is too large')
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    obj = json.loads(line)
                    if obj.get('request_id') == 11:
                        reply = obj
                        break
            if reply.get('error') != 'success': raise OSError(reply.get('error', 'Invalid reply'))
            if action == 'status':
                if type(reply.get('data')) is not bool: raise OSError('Invalid pause state')
                result[name] = reply['data']
            else: result[name] = cmd[-1]
    except (OSError, ValueError) as error:
        print(name + ': ' + str(error), file=sys.stderr)
        failed = True
if '--json' in sys.argv or action == 'restore': print(json.dumps(result))
elif action == 'status':
    for name, value in result.items(): print(name, 'paused' if value else 'playing')
    if not paths: print('no video wallpapers with IPC')
sys.exit(1 if failed else 0)
PY
