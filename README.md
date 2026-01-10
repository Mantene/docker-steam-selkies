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

**Environment variables**
- `PUID=99`
- `PGID=100`
- `TZ=Etc/UTC`

Optional (Selkies base image features):
- `CUSTOM_USER=abc` and `PASSWORD=abc` (basic auth)
- `TITLE=Steam`
- `PIXELFLUX_WAYLAND=true` (Wayland session)

If you plan to use an Intel/AMD iGPU for acceleration, add this device mapping:
- Host path `/dev/dri` → Container path `/dev/dri`


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

## Notes
- Sunshine is started automatically by the `autostart` script and logs to `/config/sunshine.log`.
- Steam is launched via `steam-selkies`, which bootstraps the Steam runtime into `/config/.steam/debian-installation` on first run (no interactive “Install/Cancel” prompt) and writes logs to `/config/steam-selkies.log`.
