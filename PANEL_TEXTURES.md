# Panel finish textures: porting the website's 3D model changes to the app

This note is for whoever applies to this app (`~/garden_house_app`) the 3D work done on the
website redesign. The website now shows the 16 real panel finishes from the Techs Garden House
brochure as **textures on the 3D model** (wood grain, goffrato pebbling, polygrain), not just flat
colours. The app should do the same, in the 3D preview and in AR.

Source of truth: the website repo, branch `design/signature` (the same code is merged into
`design/signature-dark`).

- Local: `~/garden-house-redesign` (`git checkout design/signature`)
- GitHub (public): https://github.com/sl-ee-p/garden-house-web/tree/design/signature
- Live: https://sl-ee-p.github.io/garden-house-web/signature/configura.html

**Rule from the owner: only original assets.** Photos, models and textures come from
techs-gardenhouse.com or from the official brochure. No stock or placeholder images, ever.
The textures described here are derived from the brochure's own panel photos, so they qualify.

---

## 1. The model is the same in both projects

The app and the website start from the same CAD export (`ALL-DIVIDE.glb` from
techs-gardenhouse.com; in the app it is `tools/garden_house.source.glb`). Both group the parts by
node-name prefix: `CS-P*` = panels, `CS-S*` = structure. I checked the app's
`assets/models/garden_house.glb`: after its node transform, `paint-panels` spans
x −1.307…1.307, y 0.002…2.538, z −0.891…0.899 m. That is exactly what the website's model
has, so every number below applies to the app unchanged.

Useful facts about the geometry (metres, y up, front wall facing +z):

| What | Value |
|---|---|
| Wall frame top (level all round) | y = 2.543 |
| Roof sheet (inside the frame, slopes back) | y = 2.509 at the front, 2.363 at the back |
| Panel boards | 500 mm tall, joints at y ≈ 0.00, 0.50, 1.00, 1.50, 2.00 |
| Each board's central groove | ≈ 0.25 m above its joint, so a groove or joint every 25 cm |
| Front wall | z ≈ +0.9 · side walls x ≈ ±1.31 · back wall z ≈ −0.9 |

**The grooves are real geometry.** The CAD boards already carry the joints and the central
grooves. So the texture must show only the surface (colour + grain), never grooves.

**The CAD export has no UVs** on the panels (and the app's `optimize_glb.py` drops texture
coordinates on the paint materials anyway). UVs have to be generated (section 3).

---

## 2. The textures

### Files

| Where | What |
|---|---|
| `assets/img/finiture/tex/<id>.webp` | **The textures**: 16 files, 512 × 160 px, about 84 KB in total |
| `assets/img/finiture/<id>-160.webp`, `<id>-378.webp` | The brochure's panel photos (swatch thumbnails / source) |
| `tools/panel_textures.py` | Generator: brochure photos → textures |

(Paths relative to the website repo on `design/signature`. Raw files can be fetched from
`https://raw.githubusercontent.com/sl-ee-p/garden-house-web/design/signature/<path>`.)

### How they were made (`tools/panel_textures.py`)

The 378 × 423 brochure photo is the best resolution available (checked inside the brochure PDF).
Each photo shows one 500 mm board in the same 3/4 view.

1. **Rectify** the board face with a perspective transform. Face corners in every photo:
   TL (57,47), TR (334,62), BR (334,345), BL (57,389). These map to a flat 600 × 500 px
   rectangle, about 1 px per mm.
2. **Keep the plain lower half** of the face, rows 300–474 and columns 14–574. That is between
   the groove and the bottom edge, so there is no groove and no profile in the crop.
3. **Even out the studio lighting:** divide by a Gaussian-blurred (σ = 40 px) luminance and
   rescale to its mean. The grain stays, the light falloff goes.
4. Resize to 512 × 160 and save as WebP (q86).

**One texture tile = 0.6 m wide × 0.25 m tall in the real world**, i.e. one half-board face
(from a joint to the groove, or from the groove to the next joint).

### The 16 finishes

`id` is the texture file name. "Colour" is the flat fallback colour (sRGB), shown while the
texture loads or if it fails.

| id | Name (as shown on the site) | Colour |
|---|---|---|
| `piano-goffrato-ral9010` | Piano goffrato RAL 9010 | `#f0ece2` |
| `doga-goffrato-ral9010` | Doga centrale goffrato RAL 9010 | `#e9e4db` |
| `doga-liscio-ral9010` | Doga centrale liscio RAL 9010 | `#f2eee4` |
| `doga-liscio-ral1013` | Doga centrale liscio RAL 1013 | `#e1d8c2` |
| `doga-liscio-ral7035` | Doga centrale liscio RAL 7035 | `#c4cdca` |
| `doga-liscio-ral9006` | Doga centrale liscio RAL 9006 | `#a09d9c` |
| `piano-liscio-ral9006` | Piano liscio RAL 9006 | `#a09d9c` |
| `doga-polygrain-ral7016` | Doga centrale polygrain RAL 7016 | `#3c3d3b` |
| `piano-polygrain-ral7016` | Piano polygrain RAL 7016 | `#3c3d3b` |
| `doga-goffrato-ral6005` | Doga centrale goffrato RAL 6005 | `#1a4539` |
| `doga-goffrato-ral6009` | Doga centrale goffrato RAL 6009 | `#183020` |
| `piano-liscio-noce-chiaro` | Piano liscio Noce chiaro | `#6d4324` |
| `doga-liscio-noce-chiaro` | Doga centrale liscio Noce chiaro | `#6e4325` |
| `piano-liscio-noce-scuro` | Piano liscio Noce scuro | `#573f27` |
| `doga-liscio-noce-scuro` | Doga centrale liscio Noce scuro | `#4c351f` |
| `doga-goffrato-ral8014` | Doga centrale goffrato RAL 8014 | `#302214` |

"Doga centrale" = board with a central groove (25 cm look); "piano" = plain 50 cm board. The
website's default is `doga-goffrato-ral9010`.

**Known limit:** the CAD model always has the central groove, so the "piano" finishes show the
right colour and grain but still show that groove in 3D. Same on the website.

---

## 3. What the website's viewer does (reference implementation)

File: `tools/viewer/viewer3d.js` on `design/signature` (bundled into `js/viewer3d.js` with
three.js 0.170). The relevant parts:

### UVs: box mapping in world space, per triangle

`addPanelUVs(mesh)` runs once on every mesh with the panel material:

1. De-index the geometry (`toNonIndexed()`), so each triangle owns its 3 vertices.
2. For each triangle, take its world-space face normal and pick the dominant axis:
   - |n.y| largest (tops, groove ledges): `u = x`, `v = z`
   - |n.x| largest (side walls): `u = z`, `v = y`
   - otherwise (front/back walls): `u = x`, `v = y`
3. `u /= 0.6`, `v /= 0.25` (the tile size above).
4. **Row shift**, so knots and grain don't line up row after row like wallpaper.
   - `row = floor(centroid.y / 0.25)`
   - `wall = |n.x| > |n.z| ? sign(n.x) + 3 : sign(n.z)`
   - `shift = (sin(row * 12.9898 + wall * 78.233) * 43758.5453) % 1` (a stable pseudo-random
     number per row and wall)
   - `u += shift * 4`

   Any stable per-row offset works; the exact formula doesn't matter. It must be per triangle
   (centroid), not per vertex: vertices on a joint belong to two rows.

### Sampling

- `wrapS = wrapT = MirroredRepeatWrapping`: the tile is mirrored at every repeat, so the edges
  never show a seam. Vertically that means every other 25 cm row is upside down, which is
  invisible on these finishes.
- `colorSpace = SRGB`, anisotropy up to 8.

### Material switching

- `setColors({ structure, panel, panelTexture })`: when `panelTexture` is a URL, the panel
  material gets `map = texture` and `color = white`.
- Until the texture has loaded, the flat colour stays, so the switch never flashes white.
- Textures are cached per URL. A stale load (the user picked another finish meanwhile) is
  ignored.
- With no texture, it goes back to `map = null` and the flat colour.
- Panel `roughness = 0.55`, structure `roughness 0.42 / metalness 0.15`.

### Other model changes on that branch (earlier, optional for the app)

- `tools/viewer/prep-model.mjs`: the CAD export has **no glazing**. Its only glass is a stray
  sliver on the back wall. Signature drops the sliver and adds real panes as thin boxes:
  - window: min (−0.753, 0.478, 0.868), max (−0.602, 1.967, 0.874)
  - door (top half): min (−0.014, 1.035, 0.876), max (0.693, 1.905, 0.882)
  - The viewer renders them as dark reflective glass with a faint diagonal sheen.

  The app's model currently has no glass material at all, so this is a separate, optional
  improvement.
- Studio environment lighting (three.js `RoomEnvironment`) and ACES tone mapping. The app uses
  model-viewer's own lighting/skybox, so there is nothing to port here.

### Not part of the 3D model

The website's 2D drawing ("Disegno") also got the textures (SVG patterns), a ground shadow
that follows the footprint and a roof sheet sloping down to the back. The app has no 2D drawing,
so **ignore those**.

---

## 4. How to apply it in the app

The app has two render paths, and both need the texture:

- **3D preview:** `HouseViewer` → model-viewer in a WebView. It loads the bundled
  `assets/models/garden_house.glb` once and changes materials live through model-viewer's JS
  API (`window.setPaints` in `lib/house_viewer.dart`).
- **AR:** `HouseModel.exportGlb()` → `GlbRecolorer.build()` (`lib/glb_recolor.dart`) writes a GLB
  by editing only the JSON chunk. ar_flutter_plugin_2 loads it from a file.

Suggested steps (adapt as you see fit):

### 4.1 Texture assets

- **Don't put WebP in a GLB:** core glTF only allows PNG/JPEG (WebP needs `EXT_texture_webp`,
  which AR viewers may not support).
- Convert the 16 textures to **JPEG**, e.g. `assets/textures/<id>.jpg`.
- **Pre-mirror them into a 2 × 2 tile** (1024 × 320: original | flipped-horizontally on top,
  the vertically flipped pair below). Then plain `REPEAT` gives the same seamless result as
  mirrored repeat, and you don't depend on every renderer (Sceneform/Filament in AR, ARKit,
  model-viewer) honouring `MIRRORED_REPEAT`. A pre-mirrored tile covers **1.2 m × 0.5 m**.
- Add them to `pubspec.yaml` `assets:`. `AssetServer._types` already serves `jpg`.
- For the finish picker's thumbnails, the brochure photos (`<id>-160.webp`) work as Flutter
  images (Flutter decodes WebP).

### 4.2 UVs in `tools/optimize_glb.py`

Bake the UVs at build time rather than computing them at runtime (model-viewer can't generate
UVs, and AR uses the file as is).

- For the `paint-panels` group, emit `TEXCOORD_0` with the box mapping + row shift from §3, using
  the **pre-mirrored tile size**: `u = coord / 1.2 + shift`, `v = y / 0.5`.
- Things in the script that need changing:
  - `textured()` returns `False` for paint materials, and the docstring says texture
    coordinates of untextured materials are dropped. Exempt `paint-panels`.
  - Positions are already baked to world space in `add_mesh`, which is where you have what you
    need.
  - UVs are per triangle, so emit 3 new vertices per triangle for this group (or key on
    (position, normal, uv)). `quantize_group` already welds by the full attribute tuple, so
    vertices that end up identical are still merged.
  - Keep UVs as float VEC2: `KHR_mesh_quantization` allows it, and the quantized path only
    special-cases POSITION/NORMAL.
  - Take the face normal from the stored vertex normals (or account for `det < 0`): the script
    flips winding for mirrored transforms, so a raw cross product can point inward.
- Leave the default panel material untextured, with its flat colour. The texture is applied at
  runtime.
- Regenerate: `python3 -I tools/optimize_glb.py tools/garden_house.source.glb assets/models/garden_house.glb`

### 4.3 Data model (`lib/glb_recolor.dart`, `lib/house_model.dart`, `lib/palette.dart`)

- Give `Paint` an optional texture id (e.g. `String? texture`, one of the 16 ids).
  - It must be part of `==`/`hashCode` and `toJson`/`fromJson`.
  - `fromJson` must accept configs saved before the change (no key → no texture), since
    `last_config`, favourites and undo history are stored as JSON.
- When a texture is set, `color` should hold that finish's fallback colour (table above), so
  everything that shows a colour (swatches, share text, `swatchName`) still works.
- Only panels get textures. The structure stays a flat colour, as on the website.
- Add the 16 finishes as a list in `palette.dart` (id, name, fallback colour), and a way to pick
  them in the panels picker (`lib/color_picker.dart`). The existing free colours can stay. How
  to present the two in the UI is a product decision for the owner.

### 4.4 3D preview (`lib/house_viewer.dart`)

Pass the texture URL with the paints (from `AssetServer.instance.url('assets/textures/<id>.jpg')`)
and extend `apply()` in the injected JS. A sketch:

```js
const textures = {};  // url -> Promise<Texture>, cache
async function applyTexture(material, url) {
  const slot = material.pbrMetallicRoughness.baseColorTexture;
  if (!url) { slot.setTexture(null); return; }
  textures[url] ??= viewer.createTexture(url);
  const tex = await textures[url];
  if (paints[material.name]?.t !== url) return;    // superseded meanwhile
  slot.setTexture(tex);
  material.pbrMetallicRoughness.setBaseColorFactor([1, 1, 1, 1]);
}
```

- Keep the flat `baseColorFactor` until the texture is set (no white flash), as the website does.
- The skybox already comes from the same loopback server, so CORS is handled
  (`Access-Control-Allow-Origin: *`).
- Note: the non-interactive viewer is built without the asset server (`_build(null)`). It will
  need the server too if it should show textures.

### 4.5 AR export (`GlbRecolorer.build`)

Today it only rewrites the JSON. For a textured paint it must also embed the image:

1. Append the JPEG bytes to the BIN chunk, 4-byte aligned, and grow `buffers[0].byteLength`.
2. Add a `bufferViews` entry for it.
3. Add (create the arrays if missing):
   - `images`: `{bufferView, mimeType: "image/jpeg"}`
   - `samplers`: `{wrapS: 10497, wrapT: 10497}` (REPEAT, because the tile is pre-mirrored)
   - `textures`: `{source, sampler}`
4. Set the panel material's `pbrMetallicRoughness.baseColorTexture = {index}` and
   `baseColorFactor = [1, 1, 1, 1]`.

The source GLB already has images (`KHR_texture_transform` is in use on another material), so
append to those arrays rather than replacing them. Keep `extensionsRequired`
(`KHR_mesh_quantization`). `exportGlb` already caches by paints; including the texture id in
`Paint` keeps that working. Then check on a device that ARCore (and ARKit, if built) shows the
texture.

### 4.6 Check

- [ ] Every finish shows its grain in the preview, at the right scale. Compare with the website
      configurator: one knot pattern per ~0.6 m, rows visibly offset, no seams.
- [ ] Switching finishes doesn't flash white; switching back to a plain colour removes the
      texture.
- [ ] Undo, favourites, sharing and app restart restore the finish.
- [ ] AR shows the same texture (export a GLB and inspect it, e.g. in https://gltf-viewer.donmccurdy.com).
- [ ] Old saved configs (without a texture) still load.
- [ ] Model size: 16 JPEG textures at 1024 × 320 should be well under 1 MB in total; only the
      chosen one goes into an exported GLB.
