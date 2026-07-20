# RealityKitContent

Reality Composer Pro assets for Float. Loaded at runtime via `realityKitContentBundle`.

## TODO — author the `Stereo360` material (per-eye stereo 360)

`SpatialImageEnvironment` will use a ShaderGraph material named **`Stereo360`** to render the
imported Apple Spatial skies with real per-eye stereo. Until it exists, the app falls back to
a mono skybox (no build break). To create it:

1. Open this package in **Reality Composer Pro** (open `Float.xcodeproj`, expand the
   `RealityKitContent` package, double-click the `.rkassets`; or open the package directly).
2. Create a new material file named **`Stereo360.usda`** with a material prim named
   **`Stereo360`** (so its path is `/Root/Stereo360` — that's what the loader asks for).
3. In the material's shader graph:
   - Add two **Image** (Texture2D) nodes. On each, **promote** the texture input to a
     material parameter. Name them exactly **`LeftEye`** and **`RightEye`**.
   - Add a **Camera Index Switch** node (search the node library for "camera index").
   - Wire `LeftEye` color → Camera Index Switch **input 0**; `RightEye` color → **input 1**.
   - Add an **Unlit Surface** node. Wire the Camera Index Switch output → Unlit Surface color,
     and Unlit Surface → the material's surface output.
4. Save. Rebuild the app. `SpatialImageEnvironment` sets `LeftEye`/`RightEye` at runtime from
   CGImage indices 0 (left) / 1 (right) of the selected `imported_spatial_N.heic`.

If the eyes look swapped on device, swap the two Camera Index Switch inputs (or the parameter
assignment in code). The parameter names and prim path must match `SpatialImageEnvironment`.

You can delete `Placeholder.usda` once `Stereo360.usda` exists (it's only there so the empty
`.rkassets` compiles before the real material is authored).
