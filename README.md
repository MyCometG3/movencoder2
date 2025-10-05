# movencoder2

This is a simple mov file transcoder - subset of ffmpeg project or "reinvent a wheel".

## Source Tree Layout

The project now features a clear separation between **public** and **internal** APIs, making it suitable for framework distribution and external use.

### Directory Structure

```
movencoder2/
  Public/               # 🔓 Public API headers (stable interface)
    MovEncoder2.h       # Umbrella header
    METranscoder.h      # Main transcoding controller
    MEVideoEncoderConfig.h  # Type-safe configuration
    METypes.h           # Public type definitions
  Config/               # 🔒 Internal: Types & encoder configuration
  Core/                 # 🔒 Internal: Central orchestration & core logic
  Pipeline/             # 🔒 Internal: Encoding / filtering pipeline components
  IO/                   # 🔒 Internal: Input / Output & channel abstraction
  Utils/                # 🔒 Internal: Helpers, utilities, logging, parsing
  main.m                # CLI entry point

### Public vs Internal APIs

**Public APIs** (🔓 in `Public/`):
- Stable interface suitable for external use
- Fully documented and supported
- Imported via umbrella header: `#import <MovEncoder2/MovEncoder2.h>`
- Classes: `METranscoder`, `MEVideoEncoderConfig`, `METypes`
- Progress callback types and constants

**Internal APIs** (🔒 in other directories):
- Implementation details, may change without notice
- Not intended for direct use by framework consumers
- Marked with `@internal` in header documentation

For detailed API documentation, see [docs/API_GUIDELINES.md](docs/API_GUIDELINES.md)

### Module Purpose Summary
- **Public/**: Framework public interface (METranscoder, MEVideoEncoderConfig, METypes)
- **Config/**: Type-safe encoder configuration & enums (internal implementation)
- **Core/**: Orchestration (transcoding control, manager, audio conversion - internal)
- **Pipeline/**: Encoder / filter / sample buffer pipeline components (internal)
- **IO/**: Input/Output abstractions & channel coordination (internal)
- **Utils/**: Cross-cutting utilities (logging, progress, parsing - internal)

## Features

### Movie file support
- Read/write mov file. Possibly common mp4 file would also work for read.
- All read/write is processed via AVFoundation. No compatibility issue would arise.
- Support reference movie. Both legacy QuickTime and AVFoundation based will work.

### Video transcode support
- Use either AVFoundation based encoder or libavcodec based encoder. (video)
- Support libavcodec and libx264/libx265 for video transcode.
- Support libavfilter for video filtering.
- Keep resolution and aspect ratio. No rescale.
- Keep clean aperture. No cropping.
- Keep color information. No color drift.
- Keep field information. Field count/Field mode can be preserved when transcode.
- Keep source video media timescale. No change.

### Audio transcode support
- Support AAC transcode with target bit rate.
- BitDepth conversion. i.e. 32bit to 16 bit.
- Multi Channel. Preserve original channel layout by default.
- AudioChannelLayout conversion. i.e. 5.1ch to Stereo.

## Restriction
- Video: 8bit depth only. No 10/16 bit support.
- Video: Decoded format is 2vuy/kCVPixelFormatType_422YpCbCr8 = AV_PIX_FMT_UYVY422

## Development environment

```
macOS 26.0.1 Tahoe
Xcode 26.0.1
```

## License

```
GPL v2
```

---

## Runtime requirement

```
macOS 12.xx (Monterey)
macOS 13.xx (Ventura)
macOS 14.xx (Sonoma)
macOS 15.xx (Sequoia)
macOS 26.xx (Tahoe)
```

## Required libraries

Please verify if required dylib (or symlink) are available.

```
# MacPorts
/opt/local/lib/libbz2.dylib
/opt/local/lib/liblzma.dylib
/opt/local/lib/libz.dylib

# ffmpeg/x264/x265
/usr/local/lib/libx265.dylib
/usr/local/lib/libx264.dylib
/usr/local/lib/libavdevice.dylib
/usr/local/lib/libavfilter.dylib
/usr/local/lib/libavformat.dylib
/usr/local/lib/libavcodec.dylib
/usr/local/lib/libswresample.dylib
/usr/local/lib/libswscale.dylib
/usr/local/lib/libavutil.dylib
```

## Build your own libraries HOW-TO

See HowToBuildLibs.md

---

## Command line samples

### Command line sample 1
Using AVFoundation with HW h264 encoder with yuv422, and abr mode:

    $ movencoder2 --verbose \
        --mevf "format=yuv422p, yadif=0:-1:0, format=uyvy422" \
        --ve "encode=y;codec=avc1;nclc=y;field=1;bitrate=5M" \
        --ae "encode=y;codec=aac;bitrate=192k" \
        --in /Users/foo/Movies/in.mov --out /Users/foo/Movies/out.mov

### Command line sample 2
Using libx264 with yuv420, and crf mode; x264 High profile level 4.1:

    $ movencoder2 --verbose \
        --mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
        --meve "c=libx264;r=30000:1001;o=preset=medium:profile=high" \
        --mex264 "level=4.1:vbv-maxrate=62500:vbv-bufsize=62500:crf=19:keyint=60:min-keyint=6:bframes=3" \
        --ae "encode=y;codec=aac;bitrate=192k" \
        --in /Users/foo/Movies/cam.mov --out /Users/foo/Movies/out.mov

Another form of above example:

    $ movencoder2 --verbose \
        --mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
        --meve "c=libx264;r=30000:1001;o=preset=medium:profile=high\
        :level=4.1:maxrate=62.5M:bufsize=62.5M:crf=19:g=60:keyint_min=6:bf=3"
        --ae "encode=y;codec=aac;bitrate=192k" \
        --in /Users/foo/Movies/in.mov --out /Users/foo/Movies/out.mov

### Command line sample 3
Using libx264 with yuv420, and abr mode; 1440x1080 16:9 30fps x264 High profile level 4.0 abr 5.0Mbps:

    $ movencoder2 --verbose \
        --mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
        --meve "c=libx264;r=30000:1001;par=4:3;b=5M;o=preset=medium:profile=high" \
        --mex264 "level=4.0:vbv-maxrate=25000:vbv-bufsize=25000:keyint=60:min-keyint=6:bframes=3" \
        --ae "encode=y;codec=aac;bitrate=192k" \
        --in /Users/foo/Movies/in.mov --out /Users/foo/Movies/out.mov

### Command line sample 4
Using libx264 with yuv420, and abr mode; 720x480 16:9 with c.a. 30fps x264 Main profile level 3.0 abr 2.0Mbps:

    $ movencoder2 --verbose \
        --mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
        --meve "c=libx264;r=30000:1001;par=40:33;b=2M;clean=704:480:4:0;o=preset=medium:profile=main" \
        --mex264 "level=3.0:vbv-maxrate=10000:vbv-bufsize=10000:keyint=60:min-keyint=6:bframes=3" \
        --ae "encode=y;codec=aac;bitrate=128k" \
        --in /Users/foo/Movies/SD16x9.mov --out /Users/foo/Movies/out.mov

### Command line sample 5
Using volume/gain control to boost audio by 3dB:

    $ movencoder2 --verbose \
        --ae "encode=y;codec=aac;bitrate=192k;volume=+3.0" \
        --in /Users/foo/Movies/quiet_audio.mov --out /Users/foo/Movies/louder_out.mov

Or to reduce audio by 2dB:

    $ movencoder2 --verbose \
        --ae "encode=y;codec=aac;bitrate=192k;volume=-2.0" \
        --in /Users/foo/Movies/loud_audio.mov --out /Users/foo/Movies/quieter_out.mov

---

## Options and Arguments

### Generic Options

```
-h, --help
    Show this help
-V, --verbose
    show some informative details.
-d, --debug
    set AV_LOG_DEBUG for av_log().
-D, --dump
    show internal SampleBufferChannel progress.
-i, --in <file>
    input movie file path.
-o, --out <file>
    output movie file path.
-v, --ve "args"
    Video Encoder. AVFoundation video encoder options.
-a, --ae "args"
    Audio Encoder. AVFoundation audio encoder options.
-c, --co
    Copy Others. Copy non-A/V tracks into output movie.
--meve "args"
    libavcodec based video encoder string. i.e. ffmpeg -h encoder=libx264
--mevf "args"
    libavfilter based video filter string. i.e. ffmpeg -vf "args"
--mex264 "args"
    libx264 based video encoder string. i.e. x264 -h long
--mex265 "args"
    libx265 based video encoder string. i.e. x265 -h long
```

### Arguments (--ve)

These arguments are for AVFoundation based video encoder.
Every parameters are separated by semi-colon (;).

Example: `--ve "encode=y;codec=avc1;nclc=y;field=y;bitrate=5M"`

```
encode=boolean
    transcode via AVFoundation. Should be y/yes.
codec=string
    fourCC string video encoder. i.e. avc1, hvc1, apcn, apcs, apco, ...
bitrate=numeric
    video bit rate (i.e. 2.5M, 5M, 10M, 20M, ...)
field=boolean
    put field atom into output video sampledescription.
nclc=boolean
    put nclc atom into output video sampledescription.
```

### Arguments (--ae)

These arguments are for AVFoundation based audio encoder.
Every parameters are separated by semi-colon (;).

Example: `--ae "encode=y;codec=aac;bitrate=192k"`

```
encode=boolean
    transcode audio using AVFoundation (yes/no)
codec=string
    fourCC string audio encoder. (lcpm, aac, alac, ...)
bitrate=numeric
    audio bit rate (i.e. 96k, 128k, 192k, ...)
depth=numeric
    LPCM bit depth (8, 16, 32)
layout=string
    XXX of kAudioChannelLayoutTag_XXX (AAC compatible layout name, e.g. Stereo, AAC_5_1, or integer like 8126470)
volume=numeric
    gain/volume control in dB (e.g. +3.0, -1.5, 0.0, range: -10.0 to +10.0)
```

### Arguments (--meve)

These arguments are for libavcodec based video encoder.
Every parameters are separated by semi-colon (;).

Example: `--meve "c=libx264;r=30000:1001;par=40:33;b=5M;clean=704:480:4:0;o=preset=medium:profile=high:level=4.1"`

```
c=string
    formatName or libName string video encoder. required.
    e.g. c=libx264
o=string
    video encoder options of ffmpeg. preset and profile should be here. required.
    each options are separated by colon (:).
    e.g. o=preset=medium:profile=high:level=4.1
    e.g. o=preset=medium:profile=high:level=4.1:maxrate=15M:bufsize=15M:crf=19:g=60:keyint_min=15:bf=3
    refer to: ffmpeg -encoders; ffmpeg -h encoder=libx264
r=ratio
    target frame rate for rate control. required.
    e.g. r=30000:1001, r=25:1
b=numeric
    target bit rate for rate control. only works for average bit rate encoding. optional.
    e.g. b=2.5M, b=5M, b=15M
size=width:height
    encoder native raw width:height value. optional.
    NOTE: this does not imply resize. Check only.
    e.g. size=720:480, 1920:1080
par=ratio
    pixel aspect ratio of video image in form of hRatio:vRatio. optional.
    NOTE: this does not imply update. Check only.
    e.g. par=40:33
clean=width:height:hOffset:vOffset
    put special clean aperture (clap) atom into output movie. optional.
    NOTE: This does not crop.
    e.g. clean=704,480,4,0
f=string
    same as --mevf option.
x264=string
    same as --mex264 option.
x265=string
    same as --mex265 option.
```

### Arguments (--mevf)

These arguments are for libavfilter based video filter.
Every parameters are separated by comma (,).

Example: `--mevf "format=yuv422p,yadif=0:-1:0,format=uyvy422"`

Reference: `ffmpeg -filters; ffmpeg -h filter=format; ffmpeg -h filter=yadif`

### Arguments (--mex264)

These arguments are optional, for libx264 based video encoder.

NOTE: preset and profile should be `--meve "o=preset=xxx:profile=xxx"`.

Example: `--mex264 "level=4.1:vbv-maxrate=50000:vbv-bufsize=62500:crf=19:keyint=60:min-keyint=6:bframes=3"`

Reference: `x264 -h; x264 --longhelp; x264 --fullhelp`

### Arguments (--mex265)

These arguments are optional, for libx265 based video encoder.

NOTE: preset and tune should be `--meve "o=preset=xxx:tune=xxx"`.

Reference: `x265 -h; x265 --fullhelp`

---
