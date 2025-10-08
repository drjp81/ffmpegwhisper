# README.md

## FFmpeg 8.0 (CUDA-enabled Whisper filter) in a slim, two-stage Docker image

This repo builds **FFmpeg 8.0** with a large set of codecs/filters and the **Whisper** audio-to-text filter accelerated by **GGML CUDA** (from `whisper.cpp`).
The final runtime image contains only `ffmpeg`, `ffprobe`, and the libs they actually need.

### Highlights

* **Whisper filter** (`-af whisper=…`) from `whisper.cpp v1.8.0` (CUDA build).
* **NVIDIA NVENC/NVDEC** (via `--enable-ffnvcodec` + `nv-codec-headers`) for fast GPU transcoding.
* **Intel VAAPI** enabled for hardware decode/encode on iGPUs.
* TLS via **GnuTLS** (no OpenSSL → stays redistributable under GPL).
* Packaged runtime is ~**1.5 GB** (varies), with CUDA driver libs excluded (use host injection).

---

## What’s built in (selected `./configure` flags)

**Hardware accel**

* `--enable-ffnvcodec` (NVENC/NVDEC)
* `--enable-vaapi`
* `--enable-opencl` (with ICD headers)
* `--enable-sdl2` (for dev/playback utilities)

**AI / ASR**

* `--enable-whisper` (uses `whisper.cpp` – GGML CUDA backend)

**Video codecs**

* `--enable-libaom` (AV1), `--enable-libsvtav1`, `--enable-libvpx` (VP8/9)
* `--enable-libx264`, `--enable-libx265`, `--enable-libxvid`
* `--enable-libopenh264`, `--enable-libopenjpeg` (JPEG2000)
* `--enable-libaribb24` (ARIB captions), `--enable-libdav1d` (AV1), `--enable-libdavs2`, `--enable-libxavs2`

**Audio codecs**

* `--enable-libmp3lame`, `--enable-libopus`, `--enable-libvorbis`, `--enable-libtwolame`, `--enable-libspeex`
* `--enable-libopencore-amrnb`, `--enable-libopencore-amrwb`

**Filters / Fonts / Subtitles**

* `--enable-libass`, `--enable-libfreetype`, `--enable-libfribidi`, `--enable-libharfbuzz`
* `--enable-frei0r`, `--enable-libsoxr`, `--enable-libsnappy`, `--enable-libzimg`, `--enable-libvidstab`

**Containers / misc**

* `--enable-libbluray`, `--enable-libdvdnav`, `--enable-libdvdread`
* `--enable-chromaprint`, `--enable-gnutls`, `--enable-lzma`, `--enable-zlib`
* `--enable-version3` and `--enable-gpl`

> Not included by design: **OpenSSL** (we use GnuTLS for clean GPL distribution), **Vulkan** (unset), **fdk-aac** (kept out to avoid `--enable-nonfree`).

---

## Host prerequisites (runtime)

### NVIDIA (recommended for NVENC/NVDEC)

* Install **NVIDIA Container Toolkit** on the host.
* Run containers with GPU access: `--gpus all`.
* Example:

  ```bash
  docker run --rm --gpus all ffmpeg-gpu-whisper:8.0 \
    ffmpeg -hwaccel cuda -i in.mp4 -c:v h264_nvenc out.mp4
  ```

### Intel VAAPI

* Linux host with `/dev/dri` exposed to the container:

  ```bash
  docker run --rm --device /dev/dri:/dev/dri ffmpeg-gpu-whisper:8.0 \
    ffmpeg -hwaccel vaapi -vaapi_device /dev/dri/renderD128 \
           -i in.mp4 -vf 'format=nv12,hwupload' -c:v h264_vaapi out.mp4
  ```

> On Windows (Docker Desktop), NVIDIA works via WSL2 + GPU support. For VAAPI, use a Linux host.

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
