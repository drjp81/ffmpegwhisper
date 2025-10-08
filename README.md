

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

### Linux/macOS

```bash
export DOCKER_BUILDKIT=1
docker buildx build \
  --build-arg FFMPEG_VER=8.0 \
  --build-arg AVS_TAG=v3.7.5 \
  --build-arg WHISPER_TAG=v1.8.0 \
  --build-arg CUDAARCHS=86 \
  -t ffmpeg-gpu-whisper:8.0 .
```

### PowerShell (Windows)

```powershell
$env:DOCKER_BUILDKIT="1"
docker buildx build `
  --build-arg FFMPEG_VER=8.0 `
  --build-arg AVS_TAG=v3.7.5 `
  --build-arg WHISPER_TAG=v1.8.0 `
  --build-arg CUDAARCHS=86 `
  -t ffmpeg-gpu-whisper:8.0 .
```

---

## Using the Whisper wrapper (`extract_subs.sh`)

This repo includes a small wrapper that runs FFmpeg with the Whisper audio filter to extract **SRT subtitles** next to your media file.

### Script

```sh
#!/bin/sh
# extract_subs.sh  —  wrapper for the FFmpeg Whisper filter
# Usage:
#   extract_subs.sh "<inputfile>" "<modelpath>"
# Example:
#   extract_subs.sh "/path/to/Movie (2024).mkv" "/models/ggml-large-v3-turbo.bin"

set -eu

inputfile="$1"
modelpath="$2"

if [ -z "$inputfile" ] || [ -z "$modelpath" ]; then
  echo "Usage: $0 <inputfile> <modelpath>" >&2
  exit 1
fi

inputdir=$(dirname "$inputfile")
filename=$(basename "$inputfile")
filename_noext="${filename%.*}"

cd "$inputdir"
outputfile="${filename_noext}.srt"

echo "Running Whisper → ${outputfile}"
ffmpeg -i "$inputfile" -vn \
  -af "whisper=model=${modelpath}:language=en:queue=5:destination=${outputfile}:format=srt" \
  -f null -
```

### Add the wrapper into the image

In the **runtime** stage of your Dockerfile, add:

```dockerfile
# Bundle the wrapper
COPY extract_subs.sh /usr/local/bin/extract_subs.sh
RUN chmod +x /usr/local/bin/extract_subs.sh
```

### Run it (Linux)

```bash
docker run --rm --gpus all \
  -v /path/to/videos:/videos \
  -v /path/to/models:/models \
  ffmpeg-gpu-whisper:8.0 \
  extract_subs.sh "/videos/Movie (2024).mkv" "/models/ggml-large-v3-turbo.bin"
```

### Run it (PowerShell on Windows)

```powershell
docker run --rm --gpus all `
  -v "D:\Videos:/videos" `
  -v "D:\Models:/models" `
  ffmpeg-gpu-whisper:8.0 `
  extract_subs.sh "/videos/Movie (2024).mkv" "/models/ggml-large-v3-turbo.bin"
```

> Notes
>
> * The model path must be readable in the container (bind-mount your models directory).
> * You can change `language=en` to `language=auto` to auto-detect.
> * `queue=5` tunes the filter’s worker queue (increase on bigger GPUs).

---

## Examples

**Transcode with NVENC (NVIDIA):**

```bash
docker run --rm --gpus all -v "$PWD:/work" ffmpeg-gpu-whisper:8.0 \
  ffmpeg -hwaccel cuda -i /work/in.mp4 -c:v h264_nvenc -b:v 5M -c:a aac /work/out.mp4
```

**Extract subtitles only (wrapper):**

```bash
docker run --rm --gpus all \
  -v "$PWD:/work" -v "$HOME/models:/models" ffmpeg-gpu-whisper:8.0 \
  extract_subs.sh "/work/in.mp3" "/models/ggml-large-v3-turbo.bin"
```

---

## Runtime expectations

* **CUDA driver libs** (`libcuda.so.1`, `libcudart.so.12`, `libcublas.so.12`, …) are **not** shipped in the runtime image; they come from the **host** (via `--gpus all`).
* `ffmpeg` / `ffprobe` are patched with an **RPATH** to load `/opt/ffmpeg/lib`, and the runtime sets `/etc/ld.so.conf.d/ffmpeg.conf` to the same path.

---

## Troubleshooting

* `ERROR: whisper >= 1.7.5 not found using pkg-config` during build
  Ensure the builder stage installs **nvidia-cuda-toolkit** (and optionally `nvidia-cuda-dev`). The FFmpeg configure probe links against `libggml-cuda.so` and needs CUDA libs present at **build time**.

* `libcuda.so.1 not found` at runtime
  Run with `--gpus all` and have the NVIDIA drivers/toolkit installed on the host.

* VAAPI not working
  Pass through the device: `--device /dev/dri:/dev/dri` and ensure the user has permission to access `/dev/dri/renderD128` on the host.

---

## License

* FFmpeg is built with **GPL** options and **GnuTLS** (no OpenSSL; no nonfree).
* This repo contains no FFmpeg source; it fetches official releases and builds against distro-provided libraries.
* Non-commercial, attribution JpSoftworks Inc. (Quebec Canada)

---

### Optional: verify build

Inside the container:

```bash
ffmpeg -hide_banner -buildconf | sed -n '1,120p'
ffmpeg -filters | grep -i whisper || true
ffmpeg -hwaccels
```
