# docker-steam-selkies

A minimal Steam container using the LinuxServer Selkies base (browser-streamed UI), with Sunshine included.

## What this includes
- Selkies web UI (from the base image)
- Steam via `steam-installer`
- Sunshine (latest GitHub release for Debian Trixie amd64)

## Build

### Docker (recommended for Unraid)

```bash
docker build --platform=linux/amd64 -t df-steam-selkies:local .
```

### Podman (Linux)

```bash
podman build --arch amd64 -t df-steam-selkies:local .
```

## Run on Unraid / Linux amd64

### Recommended: host networking (best for Sunshine)

This keeps Sunshine discovery and ports simple.

```bash
docker run -d \
  --name steam-selkies \
  --network host \
  -e PUID=99 -e PGID=100 \
  -e TZ=Etc/UTC \
  -v /mnt/user/appdata/steam-selkies:/config \
  df-steam-selkies:local
```

Open Selkies: `https://YOUR_UNRAID_IP:3001/`

### Bridge networking (publish ports)

If you can’t use host networking, publish Selkies + Sunshine ports:

```bash
docker run -d \
  --name steam-selkies \
  -p 3001:3001 \
  -p 47984:47984/tcp -p 47989:47989/tcp -p 48010:48010/tcp \
  -p 47998-48000:47998-48000/udp \
  -e PUID=99 -e PGID=100 \
  -e TZ=Etc/UTC \
  -v /mnt/cache/appdata/steam:/config \
  df-steam-selkies:local
```

### Unraid template-style settings (Bridge)

Use these values when adding the container in Unraid (Docker tab → Add Container / Custom).

- **Name**: `steam-selkies`
- **Repository**: `mantene/steam-selkies:latest` (or your local tag)
- **Network Type**: `bridge`
- **WebUI**: `https://[IP]:[PORT:3001]/`
- **Console shell command**: `bash`

**Port mappings**
- Container port `3001` (TCP) → Host port `3001` (TCP)  (Selkies HTTPS UI)
- Container port `47984` (TCP) → Host port `47984` (TCP) (Sunshine)
- Container port `47989` (TCP) → Host port `47989` (TCP) (Sunshine)
- Container port `48010` (TCP) → Host port `48010` (TCP) (Sunshine)
- Container port `47998` (UDP) → Host port `47998` (UDP) (Sunshine)
- Container port `47999` (UDP) → Host port `47999` (UDP) (Sunshine)
- Container port `48000` (UDP) → Host port `48000` (UDP) (Sunshine)

**Volume mappings**
- Host path `/mnt/cache/appdata/steam` → Container path `/config`

Optional (Intel/AMD iGPU / DRM render nodes):
- Host path `/dev/dri` → Container path `/dev/dri`

**Environment variables**
- `PUID=99`
- `PGID=100`
- `TZ=Etc/UTC`

Optional (Selkies base image features):
- `CUSTOM_USER=abc` and `PASSWORD=abc` (basic auth)
- `TITLE=Steam`
- `PIXELFLUX_WAYLAND=true` (Wayland session)

Optional (recommended when mapping `/dev/dri`):
- **Extra Parameters**: `--group-add=video --group-add=render`

Unraid note: group *names* resolve to GIDs **inside the container**, but `/dev/dri/*` permissions are owned by **host** GIDs. If you still get DRM/GBM `Permission denied`, add the host GIDs numerically.

On the Unraid host, run:

```bash
ls -ln /dev/dri
```

Then add the numeric group(s) shown for `card*` and `renderD*`:

- **Extra Parameters**: `--group-add=<HOST_VIDEO_GID> --group-add=<HOST_RENDER_GID>`

If you still see permission errors with `/dev/dri`, check the group owner on the Unraid host (`ls -l /dev/dri`) and ensure the container user is in that group (either via `--group-add=...` or by adjusting `PGID`).

If you’re on an older kernel/libseccomp and see GUI/DRM syscalls getting blocked, try adding:
- **Extra Parameters**: `--security-opt seccomp=unconfined`


### NVIDIA GPU (Unraid/Linux)

Unraid typically uses Docker + NVIDIA host drivers (e.g. the NVIDIA Driver plugin). A common Docker invocation is:

```bash
docker run -d \
  --name steam-selkies \
  --network host \
  --gpus all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v /mnt/cache/appdata/steam:/config \
  df-steam-selkies:local
```

If you’re using Podman on Linux instead of Docker, use the CDI-style flag: `--device nvidia.com/gpu=all`.

### Steam requirement: user namespaces

Steam requires user namespaces. If Steam exits immediately and you see `Steam now requires user namespaces`:

- On the host, check `cat /proc/sys/user/max_user_namespaces` (should be > 0).
- Some distros also require `kernel.unprivileged_userns_clone=1`.
- Container logs for the wrapper are written to `/config/steam-selkies.log`.

## Troubleshooting

### Selkies crashes with GBM/KMS permission errors

If you see errors like:

- `Failed to allocate GBM buffer: ... Permission denied`
- `KMS: DRM_IOCTL_MODE_CREATE_DUMB failed: Permission denied`

This almost always means the container can see a DRM device but doesn’t have permission to use it.

Fix (Unraid):

- Add **Device** mapping: `/dev/dri` → `/dev/dri`
- Add **Extra Parameters**: `--group-add=video --group-add=render`
- If it still fails, use numeric GIDs from the host: `--group-add=<HOST_GID>` (see note above)

For example, if `ls -ln /dev/dri` shows group `18` on `card0`/`renderD128`, add:

- **Extra Parameters**: `--group-add=18`

If it still fails:

- Verify device node permissions on the host: `ls -l /dev/dri`
- Quick isolation test: temporarily run as root (`PUID=0`, `PGID=0`). If that works, it’s definitely a permissions / group mapping issue.
- As a fallback for restrictive hosts: `--security-opt seccomp=unconfined`

If `ls -l /dev/dri` shows the device nodes are already world-writable (e.g. `crwxrwxrwx`) and you *still* get `DRM_IOCTL_MODE_CREATE_DUMB failed: Permission denied`, it’s usually not filesystem permissions — it’s the KMS/DRM ioctl being denied (capabilities/DRM master).

In that case, try one of these:

- Disable Wayland/KMS mode: remove `PIXELFLUX_WAYLAND=true` (falls back to an X11 session; this image launches KDE directly in X11 mode).
- Run the container as root (`PUID=0`, `PGID=0`) to confirm it’s a capability/KMS issue, then decide whether you want to stay root or stay on X11.

### Selkies shows a black screen (sometimes a flashing rectangle)

This usually means the UI loaded, but the video stream is not decoding or the websocket stream is failing.

1) Confirm you’re using HTTPS

- Use `https://YOUR_UNRAID_IP:3001/` (or your mapped port). Modern browser APIs (WebCodecs) require a secure context.
- If you’re using a reverse proxy, ensure it forwards websocket upgrades.

2) Try a known-good browser

- Use Chrome or Edge first.
- If you’re testing in Firefox/Safari, try Chrome to rule out codec/WebCodecs support differences.

3) Check the browser devtools

- Open DevTools → **Console**: look for WebCodecs/codec errors.
- Open DevTools → **Network** and filter for **WS**: you should see a websocket connection that stays **Open** (HTTP 101 Switching Protocols). If it’s constantly reconnecting/failing, you’ll get a black/flashy canvas.

Tip: depending on how the Selkies web UI is wired (internal reverse proxy), the data websocket connection may appear in container logs as `127.0.0.1`. Use the browser DevTools **Network → WS** view to confirm the websocket is actually open and carrying messages.

If the websocket is open but the UI **FPS stays at 0** and the WS **Messages** view shows only small control/ACK frames (e.g. `CLIENT_FRAME_ACK ...`) with no large/binary video frames, the server may simply have **nothing changing on screen** (damage-based streaming).

If you see the container logs running Wayland helper commands against **`wayland-0`** while the desktop session is clearly on **`wayland-1`** (e.g. `[svc-de] ... /config/.XDG/wayland-1 found`), Selkies can end up injecting input and running `wlr-randr` against the wrong socket. That often looks like: WS connected, but the desktop never changes (FPS stays 0).

Fix:

- `SELKIES_WAYLAND_SOCKET_INDEX=1`

Quick ways to force visible updates:

- Launch any GUI app from the Selkies **Apps** panel (to create screen damage).
- Disable browser cursors so the cursor is drawn server-side and produces damage:
  - `SELKIES_USE_BROWSER_CURSORS=false`
- Disable paint-over optimization (more bandwidth/CPU, useful for debugging):
  - `SELKIES_USE_PAINT_OVER_QUALITY=false`

4) Check container logs

- `docker logs Steam --tail=300` (or your container name)
- If you’re using Unraid, the Docker log viewer will show the same output.

Note: Selkies itself logs to container stdout/stderr by default (so `docker logs` / Unraid log viewer is the “Selkies log”). This image does not currently write a separate `/config/selkies.log` file.

If you’re in Wayland mode (`PIXELFLUX_WAYLAND=true`) and the logs show capture starting successfully but the browser is still black, try the next two toggles to isolate “decode/codec” vs “capture”.

5) Temporarily force the JPEG encoder (debug)

This bypasses H.264/WebCodecs decode paths. Add:

- `SELKIES_ENCODER=jpeg`

If JPEG works but H.264 is black, the issue is likely codec/decode support or an H.264 pipeline problem.

6) Enable Selkies debug logging

- `SELKIES_DEBUG=true`

6a) Optional smoke test (forces a visible window)

If you suspect Steam is running but not drawing a window, you can force a known GUI window to appear:

- `STEAM_DEBUG_SMOKE_TEST=true`

This launches an `xterm` window titled “Selkies Smoke Test” during session startup.

Also double-check `MAX_RES` has no trailing spaces (e.g. use `MAX_RES=1920x1080`, not `1920x1080 `), as the Wayland backend parses it as `WxH`.

7) NVENC note (NVIDIA)

If you see `Failed to init NVENC ... Falling back to CPU`, it should still stream (just slower). To improve the odds NVENC works, ensure:

- `NVIDIA_DRIVER_CAPABILITIES=all` (or at least includes `video`)

8) Clamp resolution (often fixes black stream on some GPU/driver combos)

Try adding these env vars:

- `MAX_RES=1920x1080`
- `SELKIES_MANUAL_WIDTH=1920`
- `SELKIES_MANUAL_HEIGHT=1080`

9) Increase shared memory

Some GUI/encoding pipelines behave badly with a small `/dev/shm`. Add:

- `--shm-size=1g`

Notes:

- You only need one of `-v /dev/dri:/dev/dri` **or** `--device /dev/dri:/dev/dri` (both together is redundant).

### PIXELFLUX_WAYLAND fails with `DRM_IOCTL_MODE_CREATE_DUMB ... Permission denied`

When `PIXELFLUX_WAYLAND=true`, Selkies switches into an experimental Wayland/KMS path. The error:

- `KMS: DRM_IOCTL_MODE_CREATE_DUMB failed: Permission denied`
- `Failed to allocate GBM buffer ... Permission denied`

usually means the compositor is attempting a KMS ioctl on a **render node** (e.g. `/dev/dri/renderD128`) or on a DRM card that is not KMS-capable in your setup.

Key idea:

- **KMS (modesetting)** requires opening a **card node** like `/dev/dri/card0`.
- **Rendering** typically uses a **render node** like `/dev/dri/renderD128`.
- If a KMS operation is attempted on a render node, the kernel commonly returns `EPERM` (Permission denied) even if the device node is `777`.

Try this on Unraid:

1) Identify which DRM card is the KMS device you actually want

On the Unraid host:

```bash
ls -l /dev/dri
ls -l /dev/dri/by-path
```

If you have multiple GPUs, you’ll often see multiple `card*`/`renderD*` pairs.

2) Force wlroots to use the correct KMS device

Labwc/wlroots-based compositors honor `WLR_DRM_DEVICES`. Add an env var (in Unraid template):

- `WLR_DRM_DEVICES=/dev/dri/card0`

If your KMS device is `card1` (or something else), use that instead.

Optionally also pin the render device:

- `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128`

2a) Force Pixelflux Wayland to use the correct DRM node

The Pixelflux Wayland backend (used when `PIXELFLUX_WAYLAND=true`) selects its DRM/GBM device from the `DRINODE` environment variable.

If `DRINODE` points at a render node (like `/dev/dri/renderD128`), Pixelflux can hit:

- `KMS: DRM_IOCTL_MODE_CREATE_DUMB failed: Permission denied`

because that ioctl is not allowed on render nodes.

On Unraid + NVIDIA, a reliable workaround is to point `DRINODE` at the **card** node:

- `DRINODE=/dev/dri/card0`

If your NVIDIA DRM card is not `card0`, adjust accordingly.

3) NVIDIA-specific host requirement (KMS)

If you expect KMS on NVIDIA proprietary drivers, ensure the host has `nvidia_drm` loaded with modesetting enabled.

On the Unraid host:

```bash
lsmod | grep nvidia_drm || true
cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || true
```

You want modeset to be `Y`/`1`. If it’s `N`/`0`, wlroots/KMS paths often won’t work.

Unraid fix (typical): enable the kernel module parameter and reboot.

- Go to **Main → Flash → Syslinux configuration**
- In the `append` line for your boot entry, add:

  `nvidia_drm.modeset=1`

- Reboot Unraid

After reboot, verify:

```bash
cat /sys/module/nvidia_drm/parameters/modeset
```

When this changes from `N` to `Y`, restart the container and re-test `PIXELFLUX_WAYLAND=true`. The KMS/GBM `Permission denied` errors should stop once KMS modesetting is enabled.

If it still shows `N`, check your NVIDIA Driver plugin settings/logs; some configurations can override module parameters.

4) If it still fails

- Keep `PIXELFLUX_WAYLAND=false` (X11/Openbox path). This is currently the most reliable mode on many Unraid + NVIDIA setups.
- If you want, capture the container’s startup logs around the Wayland init and share them; the key lines are the selected `/dev/dri/*` devices and any wlroots/GBM errors.

## Notes
- Sunshine is started automatically by the `autostart` script and logs to `/config/sunshine.log`.
- Steam is launched via `steam-selkies`, which bootstraps the Steam runtime into `/config/.steam/debian-installation` on first run (no interactive “Install/Cancel” prompt) and writes logs to `/config/steam-selkies.log`.
