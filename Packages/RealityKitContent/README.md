# RealityKitContent

Reality Composer Pro assets for Float. Loaded at runtime via `realityKitContentBundle`.

## `Stereo360` material — per-eye stereo 360 (DONE — hand-authored USD)

`SpatialImageEnvironment` uses a ShaderGraph material named **`Stereo360`** to render the
spatial skies with real per-eye stereo. It lives at **`Stereo360.usda`** (prim
`/Root/Stereo360`) in the `.rkassets` and compiles into the bundle with the app build.

**This was authored as hand-written USD, NOT in Reality Composer Pro** — which matters,
because RCP 3 saves a standalone binary `.tm_material` that the `.rkassets`/USD build pipeline
can't consume (that format change is what parked this for a while; see the
`rcp3-beta-format-change` note). The USD path sidesteps RCP entirely. The node graph was
recovered from the RCP-authored `Stereo360.tm_material` (strings-dump of the binary) and
rebuilt as USD. Node ids that matter:
- `ND_image_color3` ×2 — the two eye textures (`file` connected to the promoted
  `inputs:LeftEye` / `inputs:RightEye` asset params, both marked `isPublic`).
- `ND_realitykit_geometry_switch_cameraindex_color3` — the eye selector. `left`←LeftImage,
  `right`←RightImage, `mono`←LeftImage (fallback when not rendering stereo).
- `ND_realitykit_unlit_surfaceshader` — unlit (a skybox at infinity must not take scene light).

The loader (`SpatialImageEnvironment`) sets `LeftEye`/`RightEye` at runtime from CGImage
indices 0 (left) / 1 (right) of the selected spatial HEIC.

**Validating changes:** compile the assets directly without a full Xcode build —
`realitytool compile --platform xrsimulator --deployment-target 27.0 -o /tmp/out.reality <.rkassets>`
(exit 0 + empty log = clean). The **simulator cannot render distinct eyes**, so per-eye
correctness (and whether the eyes are swapped) is a **device-only** check. If eyes look
swapped on device, swap `left`/`right` connections in `Stereo360.usda` (or the param names
in code).

`Placeholder.usda` can be deleted now that `Stereo360.usda` exists (it was only there so the
empty `.rkassets` compiled).
