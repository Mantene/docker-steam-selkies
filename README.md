# docker-steam-selkies

A minimal Steam container using the LinuxServer Selkies base (browser-streamed UI), with Sunshine included.

## What this includes
- Selkies web UI (from the base image)
- Steam via `steam-installer`
- Sunshine (latest GitHub release for Debian Trixie amd64)

## Build

If you haven't started Podman yet on macOS:

```bash
podman machine init --now
```

```bash
podman build --arch amd64 -t df-steam-selkies:local .
```

If you prefer Docker:

```bash
docker build --platform=linux/amd64 -t df-steam-selkies:local .
```

## Run (basic)

```bash
podman run --rm -it \
  -p 3001:3001 \
  -v "$PWD/config:/config" \
  df-steam-selkies:local
```

Open: `https://localhost:3001/`

## Running on macOS (CPU-only)

This is the best way to validate the Selkies UI + Steam startup on a Mac. GPU passthrough and Sunshine game streaming are generally not useful on macOS because everything runs inside the Podman VM.

```bash
podman run --rm -it \
  -p 3001:3001 \
  -v "$PWD/config:/config" \
  df-steam-selkies:local
```

## Running on Linux amd64 (GPU + Sunshine)

For Sunshine, the simplest approach is host networking so discovery/streaming ports “just work”:

```bash
podman run --rm -it \
  --network host \
  -v "$PWD/config:/config" \
  df-steam-selkies:local
```

If you can’t use host networking, publish the Sunshine ports (TCP `47984`, `47989`, `48010` and UDP `47998-48000`) in addition to `3001`.

### NVIDIA GPU (Linux host)

This requires NVIDIA drivers on the host and NVIDIA container integration for Podman (either CDI or the OCI hook).

CDI-style example:

```bash
podman run --rm -it \
  --network host \
  --device nvidia.com/gpu=all \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v "$PWD/config:/config" \
  df-steam-selkies:local
```

If your host uses the OCI hook instead of CDI, you’ll typically add:
- `--hooks-dir=/usr/share/containers/oci/hooks.d/`

## Notes
- On Apple Silicon, build with `podman build --arch amd64 ...` (Steam + Sunshine are amd64 here).
- Sunshine is started automatically by the `autostart` script and logs to `/config/sunshine.log`.

## Notes
- This image currently targets `amd64` only.
- Sunshine logs go to `/config/sunshine.log`.
