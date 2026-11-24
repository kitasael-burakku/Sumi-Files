#!/usr/bin/env python3
"""infinite-input — lector de entrada privilegiado y mínimo para Infinite Desktop.

Corre como servicio del sistema (infinite-input.service: usuario dinámico en el
grupo "input", sin red, solo lectura de /dev/input). Lee teclados y ratones y
reenvía por un socket Unix SOLO lo que infinite_desktop_core.py necesita:

    K <código> <0|1>   modificadores Super/Alt/Ctrl (izq./der.), pulsado/soltado
    B <0|1>            botón izquierdo del ratón
    R <dx> <dy>        movimiento relativo del ratón, sumado por SYN_REPORT

Cualquier otra tecla (letras, números, contraseñas…) se descarta en cuanto se
lee: nunca se guarda ni se envía. Así el usuario de la sesión no necesita
pertenecer al grupo "input", que daría a CUALQUIER programa suyo acceso a todo
el teclado.

La copia que se ejecuta vive en /usr/local/lib/infinite-desktop/ (de root); la
de ~/.config/hypr/infinite_desktop/system/ es solo la fuente, que install.sh copia.

Uso:
  (systemd)  python3 -I input_reader.py              # socket heredado en fd 3
  (pruebas)  python3 -I input_reader.py --listen /ruta/al.sock
"""
import argparse
import os
import selectors
import socket
import sys
import time

from evdev import InputDevice, ecodes, list_devices

# Lista blanca. Cualquier código fuera de aquí no sale del lector.
MODIFIERS = {
    ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA,   # 125, 126
    ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT,     # 56, 100
    ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL,   # 29, 97
}
BTN_LEFT = ecodes.BTN_LEFT

# Misma cadencia de rescaneo que tenía infinite_desktop_core.py: rápido al
# principio (los receptores 2.4G tardan en enumerar), después más lento.
WARMUP_DURATION = 20.0
WARMUP_INTERVAL = 0.5
RESCAN_INTERVAL = 3.0

# Si un cliente deja de leer y su cola pasa de esto, se le desconecta: el
# lector nunca debe bloquearse por culpa de un cliente lento.
CLIENT_BUFFER_LIMIT = 256 * 1024


def log(msg):
    print(msg, flush=True)


def classify_device(dev):
    """'mouse', 'keyboard' o None, según capacidades (misma regla que usaba el
    core): ratón = REL_X+REL_Y+BTN_LEFT; teclado "real" = A, Z, LEFTSHIFT y
    alguna tecla Meta (excluye las interfaces auxiliares Consumer/System
    Control de muchos receptores)."""
    caps = dev.capabilities()
    keys = set(caps.get(ecodes.EV_KEY, []))
    rels = set(caps.get(ecodes.EV_REL, []))
    if ecodes.REL_X in rels and ecodes.REL_Y in rels and BTN_LEFT in keys:
        return "mouse"
    if (ecodes.KEY_A in keys and ecodes.KEY_Z in keys and ecodes.KEY_LEFTSHIFT in keys
            and (ecodes.KEY_LEFTMETA in keys or ecodes.KEY_RIGHTMETA in keys)):
        return "keyboard"
    return None


class Filter:
    """Convierte eventos evdev de UN dispositivo en líneas del protocolo.
    Lógica pura (sin E/S) para poder probarla con eventos sintéticos."""

    def __init__(self, kind):
        self.kind = kind
        self.pressed = set()   # modificadores / BTN_LEFT pulsados en este dispositivo
        self.dx = 0
        self.dy = 0

    def feed(self, etype, code, value):
        """Devuelve una lista de líneas (str, terminadas en '\\n') a emitir."""
        out = []
        if self.kind == "keyboard":
            if etype == ecodes.EV_KEY and code in MODIFIERS and value in (0, 1):
                (self.pressed.add if value else self.pressed.discard)(code)
                out.append(f"K {code} {value}\n")
        elif self.kind == "mouse":
            if etype == ecodes.EV_KEY and code == BTN_LEFT and value in (0, 1):
                (self.pressed.add if value else self.pressed.discard)(code)
                out.append(f"B {value}\n")
            elif etype == ecodes.EV_REL and code == ecodes.REL_X:
                self.dx += value
            elif etype == ecodes.EV_REL and code == ecodes.REL_Y:
                self.dy += value
            elif etype == ecodes.EV_SYN and code == ecodes.SYN_REPORT and (self.dx or self.dy):
                out.append(f"R {self.dx} {self.dy}\n")
                self.dx = self.dy = 0
        return out

    def snapshot(self):
        """Líneas que describen lo que está pulsado ahora (para clientes nuevos)."""
        return [f"B 1\n" if c == BTN_LEFT else f"K {c} 1\n" for c in sorted(self.pressed)]

    def release_all(self):
        """Líneas que sueltan todo lo pulsado (al desconectarse el dispositivo)."""
        lines = [f"B 0\n" if c == BTN_LEFT else f"K {c} 0\n" for c in sorted(self.pressed)]
        self.pressed.clear()
        self.dx = self.dy = 0
        return lines


class Reader:
    def __init__(self, listener):
        self.sel = selectors.DefaultSelector()
        listener.setblocking(False)
        self.sel.register(listener, selectors.EVENT_READ, ("listen", listener))
        self.devices = {}   # path -> (InputDevice, Filter)
        self.clients = {}   # socket -> bytearray (cola de salida)

    # ── dispositivos ─────────────────────────────────────────────────────────
    def rescan(self):
        for path in list_devices(writable=False):
            if path in self.devices:
                continue
            try:
                dev = InputDevice(path, readonly=True)
                kind = classify_device(dev)
            except OSError:
                continue
            if kind is None:
                dev.close()
                continue
            self.devices[path] = (dev, Filter(kind))
            self.sel.register(dev.fd, selectors.EVENT_READ, ("dev", path))
            log(f"[+] {kind}: {path} ({dev.name})")

    def drop_device(self, path):
        dev, flt = self.devices.pop(path)
        try:
            self.sel.unregister(dev.fd)
        except (KeyError, ValueError):
            pass
        try:
            dev.close()
        except OSError:
            pass
        self.broadcast(flt.release_all())
        log(f"[-] {flt.kind}: {path}")

    def read_device(self, path):
        dev, flt = self.devices[path]
        try:
            for ev in dev.read():
                self.broadcast(flt.feed(ev.type, ev.code, ev.value))
        except BlockingIOError:
            pass
        except OSError:          # ENODEV: desconectado
            self.drop_device(path)

    # ── clientes ─────────────────────────────────────────────────────────────
    def accept(self, listener):
        try:
            conn, _ = listener.accept()
        except (BlockingIOError, InterruptedError):
            return
        conn.setblocking(False)
        self.clients[conn] = bytearray()
        self.sel.register(conn, selectors.EVENT_READ, ("client", conn))
        snap = [line for _, flt in self.devices.values() for line in flt.snapshot()]
        self.queue(conn, "".join(snap).encode())
        log(f"cliente conectado ({len(self.clients)} en total)")

    def drop_client(self, conn, why):
        self.clients.pop(conn, None)
        try:
            self.sel.unregister(conn)
        except (KeyError, ValueError):
            pass
        conn.close()
        log(f"cliente desconectado: {why}")

    def queue(self, conn, data):
        buf = self.clients.get(conn)
        if buf is None or not data:
            return
        buf += data
        self.flush(conn)

    def flush(self, conn):
        buf = self.clients.get(conn)
        if buf is None:
            return
        try:
            while buf:
                n = conn.send(buf)
                del buf[:n]
        except BlockingIOError:
            pass
        except OSError as e:
            self.drop_client(conn, e.strerror or str(e))
            return
        if len(buf) > CLIENT_BUFFER_LIMIT:
            self.drop_client(conn, "no lee (cola llena)")
            return
        want = selectors.EVENT_READ | (selectors.EVENT_WRITE if buf else 0)
        self.sel.modify(conn, want, ("client", conn))

    def client_event(self, conn, mask):
        if mask & selectors.EVENT_READ:
            try:
                data = conn.recv(4096)       # el protocolo es de un solo sentido;
            except BlockingIOError:          # lo que mande el cliente se ignora
                data = b"x"
            except OSError:
                data = b""
            if not data:
                self.drop_client(conn, "cerró la conexión")
                return
        if mask & selectors.EVENT_WRITE:
            self.flush(conn)

    def broadcast(self, lines):
        if not lines:
            return
        data = "".join(lines).encode()
        for conn in list(self.clients):
            self.queue(conn, data)

    # ── bucle principal ──────────────────────────────────────────────────────
    def run(self):
        start = time.monotonic()
        next_scan = 0.0
        while True:
            now = time.monotonic()
            if now >= next_scan:
                self.rescan()
                interval = WARMUP_INTERVAL if now - start < WARMUP_DURATION else RESCAN_INTERVAL
                next_scan = now + interval
            for key, mask in self.sel.select(timeout=max(0.0, next_scan - time.monotonic())):
                kind, ref = key.data
                if kind == "dev":
                    if ref in self.devices:
                        self.read_device(ref)
                elif kind == "client":
                    if ref in self.clients:
                        self.client_event(ref, mask)
                else:
                    self.accept(ref)


def systemd_listener():
    if os.environ.get("LISTEN_PID") != str(os.getpid()) or os.environ.get("LISTEN_FDS") != "1":
        return None
    return socket.socket(fileno=3)


def manual_listener(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    old = os.umask(0o177)                  # socket creado ya con 0600
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(path)
    finally:
        os.umask(old)
    s.listen(4)
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--listen", metavar="RUTA", help="crear el socket aquí (pruebas, sin systemd)")
    args = ap.parse_args()
    listener = manual_listener(args.listen) if args.listen else systemd_listener()
    if listener is None:
        sys.exit("ERROR: sin socket de systemd (LISTEN_FDS) y sin --listen")
    log("infinite-input: activo (solo Super/Alt/Ctrl, clic izquierdo y movimiento del ratón)")
    Reader(listener).run()


if __name__ == "__main__":
    main()
