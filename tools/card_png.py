#!/usr/bin/env python3
"""card_png.py - draw a save-thumbnail card with no dependencies at all.

A Witcher 3 save is `<name>.sav` + `<name>.json` + `<name>.png`, and the .png is
just the menu's thumbnail: the engine looks it up by base name and scales whatever
it finds there, so *any* image becomes the picture of that save - and the picture is
visible in the load list *before* the save is loaded. That makes it the right place
to answer "whose save is this?" (the in-game side cannot: the frame is captured by
the engine, and the API scripts get - theGame.RequestScreenshotData() and friends -
is import final, read-only).

Only the standard library here, so the renamer keeps working on a bare Python:
  * a PNG writer (zlib + chunks), truecolour, no interlacing
  * a 5x7 bitmap font for the characters a save label needs, written out as
    readable rows so a human can check a glyph by eye
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

# 5 wide x 7 tall, '1' = ink. Lower case is drawn as its upper-case glyph.
GLYPHS: dict[str, tuple[str, ...]] = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11111", "00010", "00100", "00010", "00001", "10001", "01110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
    ",": ("00000", "00000", "00000", "00000", "01100", "01100", "01000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
    "=": ("00000", "00000", "11111", "00000", "11111", "00000", "00000"),
    ":": ("00000", "01100", "01100", "00000", "01100", "01100", "00000"),
    "!": ("00100", "00100", "00100", "00100", "00100", "00000", "00100"),
    "?": ("01110", "10001", "00001", "00010", "00100", "00000", "00100"),
    "(": ("00010", "00100", "01000", "01000", "01000", "00100", "00010"),
    ")": ("01000", "00100", "00010", "00010", "00010", "00100", "01000"),
    "[": ("01110", "01000", "01000", "01000", "01000", "01000", "01110"),
    "]": ("01110", "00010", "00010", "00010", "00010", "00010", "01110"),
    "/": ("00001", "00010", "00010", "00100", "01000", "01000", "10000"),
    "+": ("00000", "00100", "00100", "11111", "00100", "00100", "00000"),
    "*": ("00000", "10101", "01110", "11111", "01110", "10101", "00000"),
    "'": ("00100", "00100", "00000", "00000", "00000", "00000", "00000"),
    '"': ("01010", "01010", "00000", "00000", "00000", "00000", "00000"),
}

GLYPH_W, GLYPH_H, SPACING = 5, 7, 1
DEFAULT_SIZE = (512, 288)  # only used when a save has no thumbnail to match


def parse_colour(value: str) -> tuple[int, int, int]:
    """'#rrggbb', 'rrggbb' or 'r,g,b' -> (r, g, b)."""
    text = value.strip().lstrip("#")
    if "," in text:
        parts = [int(p) for p in text.split(",")]
        if len(parts) != 3:
            raise ValueError(f"not a colour: {value!r}")
        return tuple(max(0, min(255, p)) for p in parts)  # type: ignore[return-value]
    if len(text) == 3:
        text = "".join(ch * 2 for ch in text)
    if len(text) != 6:
        raise ValueError(f"not a colour: {value!r}")
    return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def text_width(text: str, scale: int) -> int:
    return max(0, len(text) * (GLYPH_W + SPACING) * scale - SPACING * scale)


def fit_scale(text: str, avail_w: int, avail_h: int) -> int:
    per_glyph = (GLYPH_W + SPACING)
    by_width = avail_w // max(1, len(text) * per_glyph)
    by_height = avail_h // GLYPH_H
    return max(1, min(by_width, by_height))


class Canvas:
    """A tiny truecolour raster with the few operations a card needs."""

    def __init__(self, width: int, height: int, bg: tuple[int, int, int]):
        self.width, self.height = width, height
        self.rows = [bytearray(bytes(bg) * width) for _ in range(height)]

    def pixel(self, x: int, y: int, colour: tuple[int, int, int]) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            row, off = self.rows[y], x * 3
            row[off : off + 3] = bytes(colour)

    def rect(self, x0: int, y0: int, x1: int, y1: int, colour: tuple[int, int, int]) -> None:
        for y in range(max(0, y0), min(self.height, y1)):
            for x in range(max(0, x0), min(self.width, x1)):
                self.pixel(x, y, colour)

    def frame(self, inset: int, thickness: int, colour: tuple[int, int, int]) -> None:
        self.rect(inset, inset, self.width - inset, inset + thickness, colour)
        self.rect(inset, self.height - inset - thickness, self.width - inset, self.height - inset, colour)
        self.rect(inset, inset, inset + thickness, self.height - inset, colour)
        self.rect(self.width - inset - thickness, inset, self.width - inset, self.height - inset, colour)

    def text(self, text: str, x: int, y: int, scale: int, colour: tuple[int, int, int]) -> None:
        pen = x
        for ch in text:
            glyph = GLYPHS.get(ch.upper(), GLYPHS["?"])
            for gy, row in enumerate(glyph):
                for gx, bit in enumerate(row):
                    if bit == "1":
                        for dy in range(scale):
                            for dx in range(scale):
                                self.pixel(pen + gx * scale + dx, y + gy * scale + dy, colour)
            pen += (GLYPH_W + SPACING) * scale

    def png(self) -> bytes:
        raw = b"".join(b"\x00" + bytes(row) for row in self.rows)
        return (
            b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(raw, 9))
            + _chunk(b"IEND", b"")
        )


def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def png_size(path: Path) -> tuple[int, int] | None:
    """Width/height of a PNG file, straight from its IHDR (5.0 save thumbnails)."""
    try:
        head = path.read_bytes()[:24]
    except OSError:
        return None
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def render(
    width: int,
    height: int,
    text: str,
    sub: str | None = None,
    fg: tuple[int, int, int] = (245, 245, 245),
    bg: tuple[int, int, int] = (16, 20, 24),
    frame: bool = True,
) -> bytes:
    """A card: `text` as large as it fits, optional smaller `sub` line below."""
    canvas = Canvas(width, height, bg)
    margin = max(6, min(width, height) // 18)

    if frame:
        canvas.frame(max(2, margin // 3), max(2, margin // 6), tuple(c // 2 for c in fg))  # type: ignore[arg-type]

    avail_w, avail_h = width - 2 * margin, height - 2 * margin

    if sub:
        main_scale = fit_scale(text, avail_w, int(avail_h * 0.62))
        sub_scale = min(fit_scale(sub, avail_w, int(avail_h * 0.28)), max(1, main_scale // 2))
        main_h = GLYPH_H * main_scale
        sub_h = GLYPH_H * sub_scale
        gap = max(2, main_scale)
        block = main_h + gap + sub_h
        top = (height - block) // 2
        canvas.text(text, (width - text_width(text, main_scale)) // 2, top, main_scale, fg)
        sub_colour = (int(fg[0] * 0.75), int(fg[1] * 0.75), int(fg[2] * 0.75))
        canvas.text(sub, (width - text_width(sub, sub_scale)) // 2, top + main_h + gap, sub_scale, sub_colour)
    else:
        scale = fit_scale(text, avail_w, avail_h)
        canvas.text(
            text,
            (width - text_width(text, scale)) // 2,
            (height - GLYPH_H * scale) // 2,
            scale,
            fg,
        )

    return canvas.png()


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="draw a save-card PNG (no dependencies)")
    parser.add_argument("output", help="where to write the .png")
    parser.add_argument("text", help="the big text")
    parser.add_argument("--sub", help="smaller line under it")
    parser.add_argument("--size", default=f"{DEFAULT_SIZE[0]}x{DEFAULT_SIZE[1]}", help="WxH")
    parser.add_argument("--fg", default="#f5f5f5")
    parser.add_argument("--bg", default="#101418")
    parser.add_argument("--no-frame", dest="frame", action="store_false")
    args = parser.parse_args(argv)

    width, height = (int(v) for v in args.size.lower().split("x"))
    data = render(width, height, args.text, args.sub, parse_colour(args.fg), parse_colour(args.bg), args.frame)
    Path(args.output).write_bytes(data)
    print(f"{args.output}: {width}x{height}, {len(data)} B, text {args.text!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
