
# FFmpeg 8.0 (GPU + Whisper) — Docker build

This repository builds a feature-rich **FFmpeg 8.0** container with:

* **Hardware transcoding**

  * **NVIDIA NVENC/NVDEC** (`--enable-ffnvcodec`) + CUDA LLVM toolchain
  * **Intel VAAPI** and **oneVPL** (`--enable-vaapi`, `--enable-libvpl`)
* **Whisper** speech-to-text audio filter (`--enable-whisper`, via **whisper.cpp**)
* A broad set of codecs, demuxers, filters, and protocols (see below)
* **Redistributable licensing**: uses **GnuTLS** (not OpenSSL) so there’s **no `--enable-nonfree`**; the final binary can be distributed under the GPL

The final image is **slim**: only `ffmpeg`, `ffprobe`, and the exact shared libraries they need are included.

> ⚠️ **Vulkan is not enabled** in this build. If you want Vulkan/libplacebo later, you’ll need to add the relevant dev packages and `--enable-vulkan` (and typically `--enable-libplacebo`, `--enable-libshaderc`) to your configure flags.

---

## What’s inside (enabled features)

### Video encoders/decoders

* **AV1**: `libaom` (enc/dec), `librav1e` (enc), `libsvtav1` (enc), `libdav1d` (dec)
* **H.264 / H.265**: `libx264`, `libx265`, **NVENC** (e.g., `h264_nvenc`, `hevc_nvenc`)
* **VP8/VP9**: `libvpx`
* **AVS2**: `libdavs2` (dec), `libxavs2` (enc)
* **MPEG-4 ASP**: `libxvid`
* **Theora**: `libtheora`
* **OpenH264**: `libopenh264`
* **JPEG 2000**: `libopenjpeg`
* **WebP / JPEG XL**: `libwebp`, `libjxl`

### Audio encoders/decoders & DSP

* **AAC (native)**, **MP3** (`libmp3lame`), **Opus** (`libopus`)
* **Vorbis** (`libvorbis`), **Speex** (`libspeex`), **AMR-NB/AMR-WB** (`opencore-amr`)
* **MP2** (`twolame`)
* **SoX Resampler** (`libsoxr`), **Rubber Band** (time-stretch), **Game Music** (`libgme`)

### Subtitles, text & filters

* **Whisper** audio-to-text filter (`--enable-whisper`)
* **Subtitles/text**: `libass`, `freetype`, `fontconfig`, `harfbuzz`, `fribidi`
* **Stabilization**: `libvidstab`
* **Frei0r** effects
* **ARIB B-24** captions (`libaribb24`)
* **Chromaprint** (acoustic fingerprinting)

### Protocols / I/O / misc

* **SRT (GnuTLS build)**, **RIST**, **SSH**, **ZeroMQ**
* **SDL2**, **OpenAL**
* **Bluray/DVD** nav: `libbluray`, `libdvdnav`, `libdvdread`
* **GnuTLS** for TLS/HTTPS, **Zlib**, **LZMA**

### GPU stacks

* **NVIDIA**: NVENC/NVDEC headers (`nv-codec-headers`) + CUDA LLVM
* **Intel**: **VAAPI** + **oneVPL** (`libvpl`)
* **OpenCL** is enabled; **Vulkan is not** (by design in this build)

> The image also includes **AviSynth+ headers only** (no AvsCore build), which is sufficient for `--enable-avisynth`.

---

## Build

**Prerequisites**

* Docker Desktop / Docker Engine
* On Windows, build from a **WSL2** shell and keep the repo in the Linux filesystem for speed.

**Build (PowerShell)**

```powershell
$env:DOCKER_BUILDKIT="1"
docker buildx build `
  --build-arg FFMPEG_VER=8.0 `
  --build-arg CUDAARCHS=75;86;89 `
  --build-arg AVS_TAG=v3.7.3 `
  --progress=plain `
  -t ffmpeg-gpu-whisper:8.0 .
```

**Notes**

* Set `CUDAARCHS` to your target GPU SM(s) to speed up whisper.cpp and reduce binary size (e.g., `86` for RTX 30-series; `89` for RTX 40-series).
* Whisper **models are not required at build time**; mount/copy them at runtime.

---

## Run

### NVIDIA GPU (NVENC/NVDEC)

Make sure the host has the NVIDIA driver + **NVIDIA Container Toolkit**.

```bash
docker run --rm -it --gpus all ffmpeg-gpu-whisper:8.0 \
  ffmpeg -hide_banner \
         -hwaccel cuda -hwaccel_output_format cuda \
         -i input.mp4 -c:v h264_nvenc -preset p5 -cq 23 -c:a copy out.mp4
```

### Intel iGPU (VAAPI)

Expose the VAAPI device:

```bash
docker run --rm -it --device /dev/dri:/dev/dri ffmpeg-gpu-whisper:8.0 \
  ffmpeg -hide_banner \
         -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
         -i input.mp4 -vf 'format=nv12,hwupload' \
         -c:v h264_vaapi -b:v 5M out.mp4
```

### Whisper filter (speech-to-text)

Mount your Whisper model and run the filter:

```bash
docker run --rm -it -v "$PWD/models:/models" ffmpeg-gpu-whisper:8.0 \
  ffmpeg -hide_banner -i speech.wav \
         -af "whisper=model=/models/ggml-base.en.bin" -f null -
```

---

## Verify features

```bash
docker run --rm ffmpeg-gpu-whisper:8.0 ffmpeg -hide_banner -buildconf | sed -n '1,160p'
docker run --rm ffmpeg-gpu-whisper:8.0 ffmpeg -hide_banner -hwaccels
docker run --rm ffmpeg-gpu-whisper:8.0 ffmpeg -hide_banner -encoders  | grep -E 'nvenc|vaapi|svt|rav1e|x26'
docker run --rm ffmpeg-gpu-whisper:8.0 ffmpeg -hide_banner -filters   | grep whisper
```

---

## Image layout

The runtime image unpacks to:

```
/opt/bin/ffmpeg
/opt/bin/ffprobe
/opt/lib/...         # .so dependency closure
/usr/local/bin/{ffmpeg,ffprobe} -> symlinks to /opt/bin
```

This repo registers loader search paths under `/etc/ld.so.conf` to match the preserved directory structure in `/opt/lib`.
If you’d prefer a single directory, adjust the packaging step to copy libs **flat** into `/opt/ffmpeg/lib` and replace the loader config with:

```dockerfile
RUN echo "/opt/ffmpeg/lib" > /etc/ld.so.conf.d/ffmpeg.conf && ldconfig
```

---

## Licensing

* This build uses **GnuTLS** (not OpenSSL), so **no `--enable-nonfree`** is required.
* The resulting binaries are **redistributable** under the **GPL** (you already pass `--enable-gpl` and `--enable-version3`).
* If you later switch back to **OpenSSL** (`--enable-openssl`), you’ll need **`--enable-nonfree`** and **must not redistribute** the binaries/images.
* Some libraries are GPL, some LGPL/Apache-2.0/MIT, etc. By building FFmpeg with `--enable-gpl --enable-version3`, you’re distributing the combined work under **GPLv3** terms.

> Not legal advice; review your dependency set before publishing artifacts.

---

## Troubleshooting

* **SRT dev conflict**: `libsrt-gnutls-dev` and `libsrt-openssl-dev` conflict. Install **only one** (this build uses **GnuTLS**).
* **AviSynth+ headers-only**: pin a tag (e.g., `AVS_TAG=v3.7.3`) so CMake’s `VersionGen` works; build with `-DHEADERS_ONLY=ON`.
* **Windows/WSL2 performance**: build from the **WSL2** side and keep sources in the Linux filesystem; enable BuildKit cache mounts and **ccache**.
* **NVIDIA runtime**: you still need host drivers and `--gpus all` (or equivalent) at `docker run` time.

---

## Customization

* `FFMPEG_VER` — pick another FFmpeg release.
* `CUDAARCHS` — set specific SMs (e.g., `86`).
* `AVS_TAG` — pin AviSynth+ headers to a specific release.


Great call. Here’s a **drop-in README section** you can paste under “Run” (or right after “Build”). It covers **host setup** for both **NVIDIA (NVENC/NVDEC)** and **Intel VAAPI/oneVPL**, with quick verification and container run examples.

---

## Host GPU Runtime Requirements

Your container already has the right userspace bits. For **hardware transcoding**, the **host** must expose a working GPU runtime.

### NVIDIA (NVENC/NVDEC)

**Linux hosts (Ubuntu/Debian)**

1. Install the proprietary NVIDIA **driver** (from your distro or NVIDIA). Reboot if you just installed it.
   Verify:

   ```bash
   nvidia-smi
   ```

   You should see your GPU and driver version.

2. Install **NVIDIA Container Toolkit** so Docker can pass the GPU through:

   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit.gpg
   curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
     | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit.gpg] https://#' \
     | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

   sudo apt-get update
   sudo apt-get install -y nvidia-container-toolkit
   sudo nvidia-ctk runtime configure
   sudo systemctl restart docker
   ```

3. Quick test (pulls a CUDA base and runs `nvidia-smi` inside):

   ```bash
   docker run --rm --gpus all nvidia/cuda:12.5.0-base-ubuntu24.04 nvidia-smi
   ```

4. Run this image with NVENC/NVDEC enabled:

   ```bash
   docker run --rm -it --gpus all ffmpeg-gpu-whisper:8.0 \
     ffmpeg -hide_banner \
            -hwaccel cuda -hwaccel_output_format cuda \
            -i input.mp4 -c:v h264_nvenc -preset p5 -cq 23 -c:a copy out.mp4
   ```

   Tips:

   * You can be explicit (not required) with `-e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=video,compute,utility`.
   * NVENC session limits are enforced by the driver/firmware; multiple encodes may require a datacenter-class GPU.

**Windows + Docker Desktop (WSL2 backend)**

* Install a recent **NVIDIA Windows driver** (supports WSL2 GPU).
* Ensure **Docker Desktop uses WSL2** (Settings → General → “Use the WSL 2 based engine”).
* From a **WSL2 shell**, verify:

  ```bash
  docker run --rm --gpus all nvidia/cuda:12.5.0-base-ubuntu24.04 nvidia-smi
  ```
* Then run NVENC as shown above. (On Windows, VAAPI is not reliably exposed—prefer NVIDIA here.)

---

### Intel iGPU (VAAPI / oneVPL)

**Linux hosts only** (recommended path for Intel iGPU)

1. Enable iGPU in BIOS and ensure the kernel driver `i915` is loaded:

   ```bash
   lsmod | grep i915 || echo "i915 not loaded"
   ```

2. Install the **Intel Media VAAPI driver** and tools:

   ```bash
   sudo apt-get update
   sudo apt-get install -y intel-media-va-driver-non-free libva2 vainfo
   # (For very old GPUs: i965-va-driver instead of intel-media-va-driver-non-free)
   ```

3. Verify VAAPI on the **host**:

   ```bash
   vainfo | grep -E 'Driver version|Supported profile'
   ```

4. Run the container with the **DRI device passed through**:

   ```bash
   docker run --rm -it --device /dev/dri:/dev/dri ffmpeg-gpu-whisper:8.0 \
     ffmpeg -hide_banner \
            -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
            -i input.mp4 -vf 'format=nv12,hwupload' \
            -c:v h264_vaapi -b:v 5M out.mp4
   ```

   Notes:

   * Some setups expose `/dev/dri/card0` and `/dev/dri/renderD128`. The **render** node is what FFmpeg typically needs.
   * Make sure the user running Docker has permissions for `/dev/dri` (or just pass the device as above).

**Windows hosts / WSL2**

* VAAPI passthrough isn’t consistently supported under WSL2/Docker Desktop today. For Intel hardware acceleration, prefer running on a native Linux host.

---

### Whisper filter (any host)

You don’t need special host GPU steps for the Whisper filter beyond the NVIDIA/Intel runtime above (if you want GPU acceleration for whisper.cpp). At **runtime**, mount your model file(s):

```bash
docker run --rm -it -v "$PWD/models:/models" ffmpeg-gpu-whisper:8.0 \
  ffmpeg -hide_banner -i speech.wav \
         -af "whisper=model=/models/ggml-base.en.bin" -f null -
```

---

### Troubleshooting quick checks

* **NVENC not listed** in encoders:

  ```bash
  docker run --rm --gpus all ffmpeg-gpu-whisper:8.0 ffmpeg -hide_banner -encoders | grep -i nvenc
  ```

  If empty: check `nvidia-smi` in a GPU container, verify container toolkit is configured, and that your GPU supports NVENC.

* **VAAPI fails** (`Device not found` / `invalid drm node`):

  * Confirm `/dev/dri/renderD128` exists on the host.
  * Try passing only the render node:

    ```bash
    --device /dev/dri/renderD128:/dev/dri/renderD128
    ```
  * Confirm `vainfo` works on the host.

* **Permissions**: If you see “Permission denied” on `/dev/dri/*`, try:

  ```bash
  docker run --rm -it --device /dev/dri --group-add video ffmpeg-gpu-whisper:8.0 ...
  ```

---

If you want, I can fold this into your README and push a “Host GPU Setup” section directly after the Run section, or generate a one-page “GPU Quickstart” you can link from the repo.

