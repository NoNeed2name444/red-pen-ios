#!/usr/bin/env python3
"""Make the rocky planet's Earth maps (ios/RedPen/Resources/Earth) from NASA's
imagery, the same way every time.

    python3 -I tools/earth_textures.py \\
        --day world.topo.200407.3x5400x2700.jpg \\
        --clouds cloud_combined_8192.tif \\
        --lights BlackMarble_2016_3km_gray.jpg \\
        --water IMERG_land_sea_mask.nc \\
        [--out ios/RedPen/Resources/Earth]

Where each input comes from, its licence and the credit it asks for are in
Resources/Earth/SOURCES.md; the inputs themselves are not kept in the
repository. Writes, all equirectangular (longitude -180 at the left edge to
+180 at the right, latitude +90 at the top):

    earth-day.jpg     4096 x 2048  true colour, sRGB, resampled in linear light
    earth-clouds.jpg  4096 x 2048  cloud cover: 0 clear sky ... 255 overcast
    earth-lights.jpg  2048 x 1024  lights at night, sRGB-encoded, resampled in
                                   linear light (a city keeps its brightness)
    earth-water.png   2048 x 1024  open water: 0 land ... 255 water (lossless)

The app packs day and clouds into one RGBA texture, and lights and water into
one RG texture (GraphEarth.swift); the rocky planet's shader samples them
(GraphStyleShaders.rockBody).

Needs numpy and PIL. The inputs are downloaded files: run this with python3 -I
from outside the folder they are in.
"""
import argparse
import os
import struct

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

DAY = (4096, 2048)
LIGHTS = (2048, 1024)


def to_linear(c):
    """sRGB code values (0...1) to linear light."""
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    """Linear light (0...1) to sRGB code values."""
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def resize(plane, size):
    """One float plane resized with a Lanczos filter (antialiased when it
    shrinks, as PIL widens the filter by the scale)."""
    return np.asarray(Image.fromarray(plane.astype(np.float32), mode="F").resize(size, Image.LANCZOS))


def bytes8(plane):
    return Image.fromarray(np.clip(np.round(plane * 255.0), 0, 255).astype(np.uint8), mode="L")


def day(path, out):
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    linear = to_linear(rgb)
    planes = [to_srgb(resize(linear[..., k], DAY)) for k in range(3)]
    image = Image.merge("RGB", [bytes8(p) for p in planes])
    image.save(out, "JPEG", quality=92, subsampling=0, optimize=True)


def clouds(path, out):
    # a grey picture (the TIFF repeats it in R, G and B): cover is the value
    grey = np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0
    bytes8(np.clip(resize(grey, DAY), 0.0, 1.0)).save(out, "JPEG", quality=90, optimize=True)


def lights(path, out):
    # tagged sRGB: averaged as light, so a town keeps its glow when it shrinks
    grey = np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0
    small = np.clip(resize(to_linear(grey), LIGHTS), 0.0, 1.0)
    bytes8(to_srgb(small)).save(out, "JPEG", quality=92, optimize=True)


def netcdf_variable(path, name):
    """One variable of a NetCDF classic file (CDF-1 or CDF-2) as numpy."""
    data = open(path, "rb").read()
    if data[:3] != b"CDF":
        raise SystemExit(f"{path}: not a NetCDF classic file")
    version, pos = data[3], 4
    kinds = {1: ("b", 1), 2: ("S1", 1), 3: (">i2", 2), 4: (">i4", 4), 5: (">f4", 4), 6: (">f8", 8)}

    def u32():
        nonlocal pos
        pos += 4
        return struct.unpack(">I", data[pos - 4:pos])[0]

    def offset():
        nonlocal pos
        if version == 2:
            pos += 8
            return struct.unpack(">Q", data[pos - 8:pos])[0]
        return u32()

    def text():
        nonlocal pos
        n = u32()
        s = data[pos:pos + n].decode("latin-1")
        pos += (n + 3) // 4 * 4
        return s

    def skip_attributes():
        nonlocal pos
        u32()
        for _ in range(u32()):
            text()
            kind, count = u32(), u32()
            pos += (count * kinds[kind][1] + 3) // 4 * 4

    u32()  # records
    u32()
    dims = [(text(), u32()) for _ in range(u32())]
    skip_attributes()
    u32()
    found = None
    for _ in range(u32()):
        vname = text()
        ids = [u32() for _ in range(u32())]
        skip_attributes()
        kind, _size, begin = u32(), u32(), offset()
        if vname == name:
            found = ([dims[i][1] for i in ids], kinds[kind][0], begin)
    if found is None:
        raise SystemExit(f"{path}: no variable {name}")
    shape, dtype, begin = found
    count = int(np.prod(shape))
    return np.frombuffer(data, dtype=dtype, count=count, offset=begin).reshape(shape)


def water(path, out):
    # percent of each 0.1 degree cell that is water, rows south first and the
    # columns from -0.05 to 360.05 (one repeated at each end)
    mask = netcdf_variable(path, "landseamask").astype(np.float32)
    lon = netcdf_variable(path, "lon").astype(np.float64)
    lat = netcdf_variable(path, "lat").astype(np.float64)
    mask = np.where(mask < 0, 0.0, mask) / 100.0
    if lat[0] < lat[-1]:
        mask = mask[::-1]
    keep = (lon > 0) & (lon < 360)
    lon = np.where(lon[keep] > 180, lon[keep] - 360, lon[keep])
    mask = mask[:, keep][:, np.argsort(lon)]
    bytes8(np.clip(resize(mask, LIGHTS), 0.0, 1.0)).save(out, "PNG", optimize=True)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--day", required=True, help="Blue Marble: Next Generation, July 2004, 5400x2700")
    ap.add_argument("--clouds", required=True, help="Blue Marble (2002) clouds, cloud_combined_8192.tif")
    ap.add_argument("--lights", required=True, help="Black Marble 2016, grayscale, 3 km (13500x6750)")
    ap.add_argument("--water", required=True, help="GPM IMERG land-sea mask (NetCDF)")
    ap.add_argument("--out", default=os.path.join(here, "..", "ios", "RedPen", "Resources", "Earth"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    day(a.day, os.path.join(a.out, "earth-day.jpg"))
    clouds(a.clouds, os.path.join(a.out, "earth-clouds.jpg"))
    lights(a.lights, os.path.join(a.out, "earth-lights.jpg"))
    water(a.water, os.path.join(a.out, "earth-water.png"))
    for n in ("earth-day.jpg", "earth-clouds.jpg", "earth-lights.jpg", "earth-water.png"):
        p = os.path.join(a.out, n)
        with Image.open(p) as im:
            print(f"{n}: {im.size[0]}x{im.size[1]} {im.mode}, {os.path.getsize(p) / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
