#!/usr/bin/env python3
"""Draw the application icon.

The icon is generated at build time rather than committed, so what ships is
always the output of the description below and never a binary nobody can
review. Only the standard library is used: zlib writes the PNG, and the shapes
are drawn from their distance functions with 3x3 supersampling for smooth
edges.

  python3 make-icon.py <output.png> [size]
"""

import struct
import sys
import zlib

# Steam's own palette, so the icon sits naturally among the other entries on a
# SteamOS desktop.
BACKGROUND_TOP = (0x17, 0x1D, 0x25)
BACKGROUND_BOTTOM = (0x1B, 0x28, 0x38)
DEVICE = (0xDC, 0xE5, 0xEC)
SCREEN = (0x10, 0x16, 0x1D)
ACCENT = (0x66, 0xC0, 0xF4)

SUBSAMPLES = 3


def rounded_rect(cx, cy, half_w, half_h, radius):
    """Signed distance to a rounded rectangle, negative inside."""
    def distance(x, y):
        dx = abs(x - cx) - (half_w - radius)
        dy = abs(y - cy) - (half_h - radius)
        outside_x = max(dx, 0.0)
        outside_y = max(dy, 0.0)
        return (outside_x * outside_x + outside_y * outside_y) ** 0.5 \
            + min(max(dx, dy), 0.0) - radius
    return distance, (cx - half_w, cy - half_h, cx + half_w, cy + half_h)


def circle(cx, cy, radius):
    def distance(x, y):
        return ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 - radius
    return distance, (cx - radius, cy - radius, cx + radius, cy + radius)


def capsule(x1, y1, x2, y2, radius):
    """A thick line segment with round caps - the strokes of the check mark."""
    vx, vy = x2 - x1, y2 - y1
    length_squared = vx * vx + vy * vy

    def distance(x, y):
        t = 0.0 if length_squared == 0 else ((x - x1) * vx + (y - y1) * vy) / length_squared
        t = min(1.0, max(0.0, t))
        px, py = x1 + t * vx, y1 + t * vy
        return ((x - px) ** 2 + (y - py) ** 2) ** 0.5 - radius

    return distance, (min(x1, x2) - radius, min(y1, y2) - radius,
                      max(x1, x2) + radius, max(y1, y2) + radius)


class Canvas:
    def __init__(self, size):
        self.size = size
        # Straight RGBA, fully transparent to begin with: the rounded corners
        # of the background are what the desktop sees through.
        self.pixels = [[[0, 0, 0, 0] for _ in range(size)] for _ in range(size)]

    def draw(self, shape, colour_at):
        distance, (x0, y0, x1, y1) = shape
        step = 1.0 / SUBSAMPLES
        offset = step / 2.0
        weight = 1.0 / (SUBSAMPLES * SUBSAMPLES)

        for py in range(max(0, int(y0) - 1), min(self.size, int(y1) + 2)):
            row = self.pixels[py]
            for px in range(max(0, int(x0) - 1), min(self.size, int(x1) + 2)):
                coverage = 0.0
                for sy in range(SUBSAMPLES):
                    y = py + offset + sy * step
                    for sx in range(SUBSAMPLES):
                        x = px + offset + sx * step
                        if distance(x, y) <= 0.0:
                            coverage += weight
                if coverage <= 0.0:
                    continue

                red, green, blue = colour_at(px, py)
                pixel = row[px]
                # Source-over compositing on straight (non-premultiplied) RGBA.
                source_alpha = coverage
                destination_alpha = pixel[3] / 255.0
                out_alpha = source_alpha + destination_alpha * (1.0 - source_alpha)
                if out_alpha <= 0.0:
                    continue
                for channel, value in enumerate((red, green, blue)):
                    blended = (value * source_alpha
                               + pixel[channel] * destination_alpha * (1.0 - source_alpha))
                    pixel[channel] = int(round(blended / out_alpha))
                pixel[3] = int(round(out_alpha * 255))

    def to_png(self, path):
        raw = bytearray()
        for row in self.pixels:
            raw.append(0)  # filter type 0: no filtering
            for pixel in row:
                raw.extend(pixel)

        def chunk(kind, payload):
            body = kind + payload
            return (struct.pack(">I", len(payload)) + body
                    + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

        header = struct.pack(">IIBBBBB", self.size, self.size, 8, 6, 0, 0, 0)
        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", header)
               + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
               + chunk(b"IEND", b""))
        with open(path, "wb") as handle:
            handle.write(png)


def solid(colour):
    return lambda _x, _y: colour


def vertical_gradient(size, top, bottom):
    def colour_at(_x, y):
        ratio = y / (size - 1)
        return tuple(int(round(t + (b - t) * ratio)) for t, b in zip(top, bottom))
    return colour_at


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "icon.png"
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 256
    unit = size / 256.0

    def u(value):
        return value * unit

    canvas = Canvas(size)
    centre = size / 2.0

    # Backdrop: a rounded square, so the corners stay transparent.
    canvas.draw(rounded_rect(centre, centre, u(126), u(126), u(30)),
                vertical_gradient(size, BACKGROUND_TOP, BACKGROUND_BOTTOM))

    # The handheld: one wide rounded body with a screen inset and two sticks.
    canvas.draw(rounded_rect(centre, centre, u(92), u(56), u(26)), solid(DEVICE))
    canvas.draw(rounded_rect(centre, centre, u(50), u(36), u(8)), solid(SCREEN))
    canvas.draw(circle(centre - u(70), centre + u(16), u(11)), solid(SCREEN))
    canvas.draw(circle(centre + u(70), centre + u(16), u(11)), solid(SCREEN))

    # A check mark on the screen: the whole point of the tool is that the
    # handheld comes out of it ready.
    stroke = u(9)
    canvas.draw(capsule(centre - u(26), centre + u(2),
                        centre - u(8), centre + u(19), stroke), solid(ACCENT))
    canvas.draw(capsule(centre - u(8), centre + u(19),
                        centre + u(28), centre - u(19), stroke), solid(ACCENT))

    canvas.to_png(path)
    print(f"icon written: {path} ({size}x{size})")


if __name__ == "__main__":
    main()
