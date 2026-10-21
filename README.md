# Garden House

Configuratore 3D in italiano per le casette da giardino Techs Garden House.
The user shapes a garden house in 3D, shares it, asks the seller for a quote
and can see it in their own garden.

## Features

- 3D preview with orbit, preset views, fullscreen and a dimensions overlay.
- Colours for the structure and the panels, plus a custom HSV picker.
- The 16 panel finishes from the brochure, rendered as real textures.
- Surface finish (matte, satin, gloss), preset combinations and "Sorprendimi".
- Undo, and saved favourite configurations.
- Sharing of a render with the configuration text, and a quote request by
  WhatsApp, email or the share sheet (see `lib/contact.dart`).
- AR on ARCore devices, with a photo placement fallback elsewhere (and on iOS).

## Architecture (`lib/`)

| File | Role |
| --- | --- |
| `main.dart` | App entry, configurator screen, lifecycle and error handling |
| `house_model.dart` | Observable paints per part, undo, persistence, GLB export |
| `palette.dart` | Swatches, panel finishes, combos |
| `glb_recolor.dart` | Parses and recolors the GLB (used for the AR export) |
| `house_viewer.dart` | WebView with model-viewer, JS bridge, snapshots |
| `asset_server.dart` | Loopback HTTP server for assets the WebView needs |
| `color_picker.dart` | Swatch grids, finish chooser, HSV sheet |
| `saved_configs.dart` | Favourites sheet |
| `share_config.dart` | Sharing and quote request |
| `ar_screen.dart` | ARCore placement |
| `photo_screen.dart` | Place the house on a photo |
| `local_store.dart` | Small atomic JSON settings file |
| `contact.dart` | Seller's WhatsApp number and email |

## Running

```sh
flutter pub get
flutter run
```

The Dart SDK constraint is `^3.13.5`; use a recent stable Flutter.

## Vendored AR plugin

`third_party/ar_flutter_plugin_2` is a patched copy of `ar_flutter_plugin_2`.
The patches are listed in `third_party/ar_flutter_plugin_2/PATCHES.md`.

## Asset pipeline

- `tools/optimize_glb.py` flattens the CAD export
  (`tools/garden_house.source.glb`) into `assets/models/garden_house.glb`.
- `tools/make_textures.py` builds the panel textures, normal maps and picker
  thumbnails from the website's brochure-derived images.
- `PANEL_TEXTURES.md` explains the finishes and how they map to the model.

Only original assets (from techs-gardenhouse.com or the official brochure)
are used.

## Testing

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

CI (`.github/workflows/ci.yml`) runs the same checks on every push and pull
request.
