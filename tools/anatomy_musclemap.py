#!/usr/bin/env python3
"""The MuscleMap whole-body model (v1.4, MIT; Zenodo 21929873) run on a CT, slice by slice, the way the
toolbox's own mm_segment.py does it: the scan turned to RAS, brought to 1 mm in the plane (its slices kept),
each chunk of slices z-scored over its non-zero voxels, cropped to its foreground with a 20 mm margin, and
each slice labelled by a 256 x 256 Gaussian sliding window.

    segment.py <ct.nii.gz> <model.json> <weights.pth> <out.nii.gz> <z0> <z1> [chunk] [overlap]

z0 and z1 are slice indices in the RAS scan (z up). The output holds MuscleMap's label values on the 1 mm
grid, with its own affine.
"""
import json, sys, time

import numpy as np
import nibabel as nib
import torch
from scipy import ndimage
from monai.networks.nets import UNet
from monai.inferers import sliding_window_inference


def main(ct, model_json, weights, out, z0, z1, chunk=48, overlap=0.5):
    cfg = json.load(open(model_json)); m = cfg["model"]
    lut = np.array([0] + sorted({e["value"] for e in cfg["labels"]}), np.int16)
    net = UNet(spatial_dims=m["spatial_dims"], in_channels=m["in_channels"], out_channels=m["out_channels"],
               channels=m["channels"], strides=m["strides"], num_res_units=m["num_res_units"], act=m["act"],
               norm=m["norm"])
    net.load_state_dict(torch.load(weights, map_location="cpu", weights_only=True)); net.eval()
    im = nib.as_closest_canonical(nib.load(ct)); sx, sy, sz = (float(s) for s in im.header.get_zooms()[:3])
    nx, ny, nz = im.shape[:3]; z1 = min(z1, nz)
    mx, my = int(np.floor((nx - 1) * sx)) + 1, int(np.floor((ny - 1) * sy)) + 1   # 1 mm in the plane
    gx, gy = np.meshgrid(np.arange(mx) / sx, np.arange(my) / sy, indexing="ij")
    labels = np.zeros((mx, my, z1 - z0), np.int16); t0 = time.time()
    for a in range(z0, z1, chunk):
        b = min(a + chunk, z1); raw = np.asarray(im.dataobj[:, :, a:b], np.float32)
        vol = np.stack([ndimage.map_coordinates(raw[:, :, k], [gx, gy], order=1, mode="nearest")
                        for k in range(b - a)], axis=2)
        nonzero = vol != 0
        if not nonzero.any():
            continue
        mean, std = float(vol[nonzero].mean()), float(vol[nonzero].std()) or 1.0
        vol[nonzero] = (vol[nonzero] - mean) / std
        fg = np.argwhere((vol > 0).any(2))
        if not len(fg):
            continue
        (x0, y0), (x1, y1) = np.maximum(fg.min(0) - 20, 0), np.minimum(fg.max(0) + 21, (mx, my))
        crop = vol[x0:x1, y0:y1]; px, py = max(256 - crop.shape[0], 0), max(256 - crop.shape[1], 0)
        crop = np.pad(crop, ((0, px), (0, py), (0, 0)))
        with torch.no_grad():
            for k in range(b - a):
                x = torch.from_numpy(crop[:, :, k])[None, None]
                y = sliding_window_inference(x, (256, 256), 4, net, overlap=overlap, mode="gaussian")
                got = y[0].argmax(0).numpy()[:x1 - x0, :y1 - y0]
                labels[x0:x1, y0:y1, a - z0 + k] = lut[got]
        print(f"  slices {a}-{b}: {time.time() - t0:.0f} s, labels {len(np.unique(labels[:, :, a - z0:b - z0])) - 1}",
              flush=True)
    aff = im.affine.copy(); aff[:3, 0] /= sx; aff[:3, 1] /= sy; aff[:3, 3] += im.affine[:3, 2] * z0
    nib.save(nib.Nifti1Image(labels, aff), out)
    print("saved", out, labels.shape, f"{time.time() - t0:.0f} s")


if __name__ == "__main__":
    a = sys.argv
    main(a[1], a[2], a[3], a[4], int(a[5]), int(a[6]), int(a[7]) if len(a) > 7 else 48,
         float(a[8]) if len(a) > 8 else 0.5)
