#!/usr/bin/env python3
"""Flattens the CAD export of the garden house into a GLB that renders fast
on phones.

The CAD export has ~340 mesh nodes (one draw call each) and a transmissive
material, which makes model-viewer render the whole scene twice per frame.
This script:

  * drops fasteners (HARDWARE_PREFIXES), which are too small to see;
  * bakes every node's world transform into its vertices and merges all
    primitives that share a material into one, so the scene is a handful of
    draw calls;
  * gives everything under the paintable parts (node names starting with
    CS-S / CS-P) a single material each, named "paint-structure" /
    "paint-panels", which the app recolors by name;
  * replaces KHR_materials_transmission with plain alpha blending;
  * drops duplicate images;
  * drops texture coordinates of untextured materials, and gives the panels
    their own (box-mapped in world space, PANEL_TILE per texture repeat), for
    the brochure finish textures the app applies at runtime;
  * quantizes the geometry (KHR_mesh_quantization): positions to int16 on a
    grid scaled back by the node transform, normals to int8. Vertices that
    become identical are welded, and triangles that collapse are dropped.
    Pass --no-quantize to keep float geometry.

Usage: python3 -I tools/optimize_glb.py [--no-quantize] \
           tools/garden_house.source.glb assets/models/garden_house.glb
"""

import json
import math
import struct
import sys

PARTS = {"CS-S": "paint-structure", "CS-P": "paint-panels"}
# Screws, bolts, nuts and washers: ~1% of the house's size, so invisible in
# the preview and in AR, yet ~86% of the triangles and most of the draw calls.
HARDWARE_PREFIXES = ("VINO", "PINO", "IZNC", "DZNC", "VZNC", "ROPL", "DINO")
# Mirrors the default paints in lib/house_model.dart so the first frame is
# already right before the app applies the current configuration.
PART_DEFAULTS = {"paint-structure": 0x8B4513, "paint-panels": 0xF5F5F5}
# Real size of one repeat of the panel textures (assets/textures/*.jpg, which
# are pre-mirrored 2 x 2 tiles of a half-board face), in meters.
PANEL_TILE = (1.2, 0.5)
# Height of one row of the panels' joints and grooves, in meters.
PANEL_ROW = 0.25

GLB_MAGIC, JSON_CHUNK, BIN_CHUNK = 0x46546C67, 0x4E4F534A, 0x004E4942
INT8, INT16, FLOAT, UINT8, UINT16, UINT32 = 5120, 5122, 5126, 5121, 5123, 5125
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
INDEX_FORMATS = {UINT8: "B", UINT16: "H", UINT32: "I"}


def read_glb(path):
    data = open(path, "rb").read()
    magic, _, _ = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise SystemExit(f"{path}: not a GLB file")
    gltf, binary, offset = None, b"", 12
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        body = data[offset + 8 : offset + 8 + length]
        if kind == JSON_CHUNK:
            gltf = json.loads(body)
        elif kind == BIN_CHUNK:
            binary = body
        offset += 8 + length
    return gltf, binary


def read_accessor(gltf, binary, index):
    acc = gltf["accessors"][index]
    if "sparse" in acc or acc.get("normalized"):
        raise SystemExit(f"accessor {index}: sparse/normalized not supported")
    view = gltf["bufferViews"][acc["bufferView"]]
    width = COMPONENTS[acc["type"]]
    fmt = "f" if acc["componentType"] == FLOAT else INDEX_FORMATS[acc["componentType"]]
    size = struct.calcsize(fmt) * width
    stride = view.get("byteStride") or size
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    item = struct.Struct(f"<{width}{fmt}")
    return [item.unpack_from(binary, base + i * stride) for i in range(acc["count"])]


def panel_uvs(positions, normals):
    """Box mapping in world space for one panel triangle.

    Picks the plane by the dominant axis of the face normal and shifts every
    row of boards by a stable pseudo-random amount, so the grain doesn't line
    up row after row like wallpaper. Mirrors addPanelUVs() in the website's
    tools/viewer/viewer3d.js (design/signature).
    """
    # The stored normals, not a cross product: winding may have been flipped.
    n = [sum(v[c] for v in normals) for c in range(3)]
    ax, ay, az = (abs(v) for v in n)
    if ay >= ax and ay >= az:
        axes = (0, 2)  # tops and groove ledges
    elif ax >= az:
        axes = (2, 1)  # side walls
    else:
        axes = (0, 1)  # front and back walls
    cy = sum(p[1] for p in positions) / 3
    row = math.floor(cy / PANEL_ROW)
    wall = (math.copysign(1, n[0]) + 3) if ax > az else math.copysign(1, n[2])
    shift = (math.sin(row * 12.9898 + wall * 78.233) * 43758.5453) % 1
    return [
        (p[axes[0]] / PANEL_TILE[0] + shift * 2, p[axes[1]] / PANEL_TILE[1])
        for p in positions
    ]


def mat_mul(a, b):
    # Column-major 4x4, as stored by glTF.
    return [
        sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
        for c in range(4)
        for r in range(4)
    ]


def normal_matrix(m):
    """Inverse-transpose of the upper 3x3 (row-major rows), and its determinant."""
    a = [[m[c * 4 + r] for c in range(3)] for r in range(3)]
    det = (
        a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
        - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
        + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
    )
    # Cofactor matrix / det == inverse-transpose.
    cof = [
        [
            (a[(r + 1) % 3][(c + 1) % 3] * a[(r + 2) % 3][(c + 2) % 3]
             - a[(r + 1) % 3][(c + 2) % 3] * a[(r + 2) % 3][(c + 1) % 3]) / det
            for c in range(3)
        ]
        for r in range(3)
    ]
    return cof, det


def srgb_to_linear(channel):
    c = channel / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def optimize(gltf, binary, quantize=True):
    nodes = gltf["nodes"]
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    for node in nodes:
        if any(k in node for k in ("translation", "rotation", "scale")):
            raise SystemExit("TRS node transforms not supported (export uses matrices)")

    # (material key, attribute names) -> merged geometry
    groups = {}

    def walk(index, parent_matrix, part):
        node = nodes[index]
        name = node.get("name", "")
        if name.startswith(HARDWARE_PREFIXES):
            return
        for prefix, material in PARTS.items():
            if name.startswith(prefix):
                part = material
        world = mat_mul(parent_matrix, node.get("matrix", identity))
        if "mesh" in node:
            add_mesh(node["mesh"], world, part)
        for child in node.get("children", []):
            walk(child, world, part)

    def add_mesh(mesh_index, world, part):
        normals, det = normal_matrix(world)
        for prim in gltf["meshes"][mesh_index]["primitives"]:
            if prim.get("mode", 4) != 4 or "indices" not in prim:
                raise SystemExit("only indexed triangle lists are supported")
            key_material = part or prim.get("material")
            panels = key_material == "paint-panels"
            attrs = tuple(sorted(
                a for a in prim["attributes"]
                if not a.startswith("TEXCOORD") or textured(key_material)
            ) + (["TEXCOORD_0"] if panels else []))
            key = (key_material, attrs)
            group = groups.setdefault(key, {a: [] for a in attrs} | {"indices": []})
            values = {"POSITION": [
                (
                    world[0] * x + world[4] * y + world[8] * z + world[12],
                    world[1] * x + world[5] * y + world[9] * z + world[13],
                    world[2] * x + world[6] * y + world[10] * z + world[14],
                )
                for x, y, z in read_accessor(gltf, binary, prim["attributes"]["POSITION"])
            ]}
            if "NORMAL" in attrs:
                values["NORMAL"] = []
                for x, y, z in read_accessor(gltf, binary, prim["attributes"]["NORMAL"]):
                    n = [r[0] * x + r[1] * y + r[2] * z for r in normals]
                    length = math.sqrt(sum(v * v for v in n)) or 1
                    values["NORMAL"].append(tuple(v / length for v in n))
            for attr in attrs:
                if attr not in values and not (panels and attr == "TEXCOORD_0"):
                    if attr == "TANGENT":
                        raise SystemExit("TANGENT attributes not supported")
                    values[attr] = read_accessor(gltf, binary, prim["attributes"][attr])
            tris = []
            indices = [i for (i,) in read_accessor(gltf, binary, prim["indices"])]
            for t in range(0, len(indices), 3):
                a, b, c = indices[t : t + 3]
                # A mirroring transform flips the winding; undo it.
                tris.append((a, c, b) if det < 0 else (a, b, c))
            if panels:
                # UVs are per triangle, so every triangle gets its own vertices.
                for tri in tris:
                    first = len(group["POSITION"])
                    for i in tri:
                        for attr, v in values.items():
                            group[attr].append(v[i])
                    group["TEXCOORD_0"] += panel_uvs(
                        [values["POSITION"][i] for i in tri],
                        [values["NORMAL"][i] for i in tri],
                    )
                    group["indices"] += (first, first + 1, first + 2)
            else:
                first = len(group["POSITION"])
                for attr, v in values.items():
                    group[attr] += v
                for tri in tris:
                    group["indices"] += (i + first for i in tri)

    def textured(material):
        if isinstance(material, str):  # paint materials are plain colors
            return False
        return '"index"' in json.dumps(gltf["materials"][material or 0])

    scene = gltf["scenes"][gltf.get("scene", 0)]
    for root in scene["nodes"]:
        walk(root, identity, None)

    # --- materials -------------------------------------------------------
    materials, remap = [], {}
    for key, _ in groups:
        if key in remap:
            continue
        if isinstance(key, str):
            rgb = PART_DEFAULTS[key]
            mat = {
                "name": key,
                "doubleSided": True,
                "pbrMetallicRoughness": {
                    "baseColorFactor": [
                        srgb_to_linear((rgb >> 16) & 0xFF),
                        srgb_to_linear((rgb >> 8) & 0xFF),
                        srgb_to_linear(rgb & 0xFF),
                        1.0,
                    ],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.7,
                },
            }
        else:
            mat = json.loads(json.dumps(gltf["materials"][key or 0]))
            transmission = mat.get("extensions", {}).pop("KHR_materials_transmission", None)
            if transmission is not None:
                factor = transmission.get("transmissionFactor", 0)
                mat["pbrMetallicRoughness"].setdefault("baseColorFactor", [1, 1, 1, 1])[3] = 1 - factor * 0.8
                mat["alphaMode"] = "BLEND"
            if not mat.get("extensions"):
                mat.pop("extensions", None)
        remap[key] = len(materials)
        materials.append(mat)

    # --- textures / images (deduplicated) --------------------------------
    out = bytearray()
    views, accessors = [], []

    def add_view(data, target=None, stride=None):
        while len(out) % 4:
            out.append(0)
        view = {"buffer": 0, "byteOffset": len(out), "byteLength": len(data)}
        if target:
            view["target"] = target
        if stride:
            view["byteStride"] = stride
        out.extend(data)
        views.append(view)
        return len(views) - 1

    images, image_remap, seen = [], {}, {}
    for i, image in enumerate(gltf.get("images", [])):
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        data = binary[start : start + view["byteLength"]]
        if data not in seen:
            seen[data] = len(images)
            images.append({"mimeType": image["mimeType"], "bufferView": add_view(data)})
        image_remap[i] = seen[data]
    textures = [
        {"sampler": t.get("sampler", 0), "source": image_remap[t["source"]]}
        for t in gltf.get("textures", [])
    ]

    # --- geometry ----------------------------------------------------------
    node = {"name": "GardenHouse", "mesh": 0}
    if quantize:
        # One grid for the whole house, so the node transform maps it back.
        everything = [p for g in groups.values() for p in g["POSITION"]]
        lo = [min(p[c] for p in everything) for c in range(3)]
        hi = [max(p[c] for p in everything) for c in range(3)]
        center = [(a + b) / 2 for a, b in zip(lo, hi)]
        # Uniform scale: a non-uniform one would skew the normals.
        step = max(b - a for a, b in zip(lo, hi)) / 2 / 32767
        node |= {"translation": center, "scale": [step] * 3}

    primitives = []
    for (key, attrs), group in groups.items():
        indices = group["indices"]
        if quantize:
            group, indices = quantize_group(group, attrs, center, step)
        prim = {"attributes": {}, "material": remap[key], "mode": 4}
        for attr in attrs:
            values = group[attr]
            width = len(values[0])
            acc = {"count": len(values), "type": {2: "VEC2", 3: "VEC3", 4: "VEC4"}[width]}
            if quantize and attr == "POSITION":
                # int16 xyz padded to 8 bytes: attributes must be 4-aligned.
                data = b"".join(struct.pack("<4h", *v, 0) for v in values)
                acc |= {"bufferView": add_view(data, 34962, stride=8), "componentType": INT16}
            elif quantize and attr == "NORMAL":
                data = b"".join(struct.pack("<4b", *v, 0) for v in values)
                acc |= {"bufferView": add_view(data, 34962, stride=4),
                        "componentType": INT8, "normalized": True}
            else:
                data = struct.pack(f"<{len(values) * width}f", *(v for item in values for v in item))
                acc |= {"bufferView": add_view(data, 34962), "componentType": FLOAT}
            if attr == "POSITION":
                acc["min"] = [min(v[c] for v in values) for c in range(3)]
                acc["max"] = [max(v[c] for v in values) for c in range(3)]
            accessors.append(acc)
            prim["attributes"][attr] = len(accessors) - 1
        wide = len(group["POSITION"]) > 0xFFFF
        data = struct.pack(f"<{len(indices)}{'I' if wide else 'H'}", *indices)
        accessors.append({
            "bufferView": add_view(data, 34963),
            "componentType": UINT32 if wide else UINT16,
            "count": len(indices),
            "type": "SCALAR",
        })
        prim["indices"] = len(accessors) - 1
        primitives.append(prim)

    while len(out) % 4:
        out.append(0)
    used_ext = sorted(
        {e for m in materials for e in m.get("extensions", {})}
        | ({"KHR_texture_transform"} if "KHR_texture_transform" in json.dumps(materials) else set())
        | ({"KHR_mesh_quantization"} if quantize else set())
    )
    result = {
        "asset": {"version": "2.0", "generator": "garden_house_app/tools/optimize_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [node],
        "meshes": [{"name": "GardenHouse", "primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(out)}],
    }
    if images:
        result |= {"images": images, "textures": textures, "samplers": gltf.get("samplers", [{}])}
    if used_ext:
        result["extensionsUsed"] = used_ext
    if quantize:
        # Readers that can't decode int16 positions must not guess.
        result["extensionsRequired"] = ["KHR_mesh_quantization"]
    return result, bytes(out)


def quantize_group(group, attrs, center, step):
    """Snaps one merged primitive to the int grid, welding equal vertices."""
    welded = {a: [] for a in attrs}
    seen, remap = {}, []
    for i, p in enumerate(group["POSITION"]):
        vertex = {"POSITION": tuple(round((p[c] - center[c]) / step) for c in range(3))}
        if "NORMAL" in attrs:
            vertex["NORMAL"] = tuple(round(v * 127) for v in group["NORMAL"][i])
        for attr in attrs:
            if attr not in vertex:
                vertex[attr] = group[attr][i]
        key = tuple(vertex[a] for a in attrs)
        if key not in seen:
            seen[key] = len(seen)
            for a in attrs:
                welded[a].append(vertex[a])
        remap.append(seen[key])
    indices = []
    old = group["indices"]
    for t in range(0, len(old), 3):
        a, b, c = (remap[i] for i in old[t : t + 3])
        if a != b and b != c and a != c:
            indices += (a, b, c)
    return welded, indices


def write_glb(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(text), JSON_CHUNK) + text)
        f.write(struct.pack("<II", len(binary), BIN_CHUNK) + binary)


def main():
    args = [a for a in sys.argv[1:] if a != "--no-quantize"]
    if len(args) != 2:
        raise SystemExit(__doc__)
    gltf, binary = read_glb(args[0])
    result, out = optimize(gltf, binary, quantize="--no-quantize" not in sys.argv)
    write_glb(args[1], result, out)
    prims = result["meshes"][0]["primitives"]
    tris = sum(result["accessors"][p["indices"]]["count"] for p in prims) // 3
    verts = sum(result["accessors"][p["attributes"]["POSITION"]]["count"] for p in prims)
    size = 12 + 8 + len(json.dumps(result, separators=(",", ":"))) + 8 + len(out)
    print(f"{len(prims)} draw calls, {tris} triangles, {verts} vertices, "
          f"{len(result['materials'])} materials, {size / 1024:.0f} KB -> {args[1]}")


if __name__ == "__main__":
    main()
