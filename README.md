> **⚠️ This repository is no longer maintained.**  
> The Trakt website has degraded significantly with the rollout of V3 and the
> new restrictions on connected apps. I no longer use or support the platform,
> and won't be making or pushing further changes here. Feel free to fork if
> you'd like to carry this forward.

# PlexTraktSync Patched

A Docker build of [PlexTraktSync](https://github.com/Taxel/PlexTraktSync) that
clones the upstream source at build time and optionally applies community
patches — without maintaining a permanent fork.

## How it works

1. **Clone** upstream PlexTraktSync at any tag/branch
2. **Apply** `.patch` files from `Patches/` to the source
3. **Build** a minimal runtime image with the patched application

Patches live in this repo so you can version, review, and share them like any
other code — without carrying the full upstream source.

## Adding patches

1. Make changes to a local clone of PlexTraktSync
2. Generate a patch file:

   ```bash
   git diff > Patches/my-change.patch
   ```

3. Add the patch to the `Patches/` directory
4. Rebuild — all `.patch` files are applied automatically in sorted order

## Build arguments

| Arg            | Default                                    | Description                     |
|----------------|--------------------------------------------|---------------------------------|
| `PTS_VERSION`  | `main`                                     | Upstream branch or tag to clone |
| `PTS_REPO`     | `https://github.com/Taxel/PlexTraktSync.git` | Upstream repository URL         |
| `APP_VERSION`  | `unknown`                                  | Version stamped into the image  |
| `BUILD_DATE`   | *(not set)*                                | Build timestamp for labels      |
| `SOURCE_COMMIT` | *(not set)*                                | Source commit for labels        |
