#!/usr/bin/env python3
import sys
import struct
import zlib

if len(sys.argv) != 3:
    print("usage: extract_country_mask.py input.bmp.z output.bmp.z", file=sys.stderr)
    sys.exit(1)

inp, outp = sys.argv[1], sys.argv[2]

# -----------------------
# Tunables (safe defaults)
# -----------------------

BRIGHT_THRESH = 40      # minimum brightness to consider "line"
SAT_THRESH    = 20     # max(R,G,B)-min(R,G,B) allowed (kills aurora color)

# -----------------------

def rgb565_to_rgb888(p):
    r = (p >> 11) & 31
    g = (p >> 5) & 63
    b = p & 31
    return (
        (r << 3) | (r >> 2),
        (g << 2) | (g >> 4),
        (b << 3) | (b >> 2),
    )

with open(inp, "rb") as f:
    bmp = zlib.decompress(f.read())

buf = bytearray(bmp)

# BMP header fields
pix_off = struct.unpack_from("<I", buf, 10)[0]
width   = struct.unpack_from("<i", buf, 18)[0]
h0      = struct.unpack_from("<i", buf, 22)[0]

height = abs(h0)
topdown = h0 < 0

rowbytes = ((width * 2 + 3) // 4) * 4

kept = 0

for y in range(height):
    ry = y if topdown else height - 1 - y
    base = pix_off + ry * rowbytes

    for x in range(width):
        off = base + x * 2
        p = struct.unpack_from("<H", buf, off)[0]

        r, g, b = rgb565_to_rgb888(p)
        lum = (r + g + b) // 3
        sat = max(r, g, b) - min(r, g, b)

        # keep only bright *neutral* pixels (country lines)
        if lum > BRIGHT_THRESH and sat < SAT_THRESH:
            struct.pack_into("<H", buf, off, 0xFFFF)  # white
            kept += 1
        else:
            struct.pack_into("<H", buf, off, 0x0000)  # black

with open(outp, "wb") as f:
    f.write(zlib.compress(bytes(buf), 9))

print(f"OK: {outp}   white_pixels={kept}")

