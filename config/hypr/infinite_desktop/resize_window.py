#!/usr/bin/env python3
"""
resize_window.py
Redimensiona la ventana activa en pasos de 90 px.
En mosaico ajusta el reparto del layout; en flotante conserva el tamaño exacto.

left/right → changes the width
up/down    → changes the height

Usage: python3 resize_window.py <left|right|up|down>
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hypr_ipc import hyprctl_json, resize_window_exact, dispatch

STEP = 90
MIN_SIZE = 100  # minimum size so the window doesn't collapse


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("left", "right", "up", "down"):
        print("Usage: resize_window.py <left|right|up|down>")
        sys.exit(1)

    direction = sys.argv[1]

    window = hyprctl_json(["activewindow"])
    if not window:
        sys.exit(0)

    addr = window["address"]
    if not window.get("floating"):
        # El layout reparte el incremento entre las ventanas vecinas.
        dx, dy = {"left": (-STEP, 0), "right": (STEP, 0),
                  "up": (0, -STEP), "down": (0, STEP)}[direction]
        dispatch(f'hl.dsp.window.resize({{ window = "address:{addr}", '
                 f'x = {dx}, y = {dy}, relative = true }})')
        return

    ww, wh = window["size"][0], window["size"][1]

    if direction == "right":
        new_w = ww + STEP
        new_h = wh
    elif direction == "left":
        new_w = max(MIN_SIZE, ww - STEP)
        new_h = wh
    elif direction == "down":
        new_w = ww
        new_h = wh + STEP
    elif direction == "up":
        new_w = ww
        new_h = max(MIN_SIZE, wh - STEP)

    resize_window_exact(new_w, new_h, addr)


if __name__ == "__main__":
    main()
