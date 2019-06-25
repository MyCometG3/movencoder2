## movencoder2

This is a simple mov file transcoder - subset of ffmpeg project or "reinvent a wheel".

#### Features:
###### Movie file support:
- Read/write mov file. Possiblly common mp4 file would also work for read.
- All read/write is processed via AVFoundation. No compatibility issue would arise.
- Support reference movie. Both legacy QuickTime and AVFoundation based will work.

###### Video transcode support:
- Use either AVFoundation based encoder or libavcodec based encoder. (video)
- Support libavcodec and libx264/libx265 for video transcode.
- Support libavfilter for video filtering.
- Keep resolution and aspect ratio. No rescale.
- Keep clean aperture. No cropping.
- Keep color information. No color drift.
- Keep field information. Field count/Filed mode can be preserved when transcode.
- Keep source video media timescale. No change.

#### Restriction:
- Video: 8bit depth only. No 10/16 bit support.
- Video: Decoded format is 2vuy/kCVPixelFormatType_422YpCbCr8 = AV_PIX_FMT_UYVY422

#### License:
- GPL v2

---

#### Runtime requirement:
    macOS 10.13 (High Sierra), macOS 10.14 (Mojave)

#### Required libraries:
    Please verify if required dylib (or symlink) are available.

    /usr/lib/liblzma.dylib
    /usr/lib/libz.dylib
    /usr/local/lib/libavcodec.dylib
    /usr/local/lib/libavdevice.dylib
    /usr/local/lib/libavfilter.dylib
    /usr/local/lib/libavformat.dylib
    /usr/local/lib/libavutil.dylib
    /usr/local/lib/libpostproc.dylib
    /usr/local/lib/libswresample.dylib
    /usr/local/lib/libswscale.dylib
    /usr/local/lib/libx264.dylib
    /usr/local/lib/libx265.dylib

---

#### Command line sample 1
Using AVFoundation with HW h264 encoder with yuv422, and abr mode:

    $ movencoder2 -verbose \
        -mevf "format=yuv422p, yadif=0:-1:0, format=uyvy422" \
        -ve "encode=y;codec=avc1;nclc=y;field=1;bitrate=5M" \
        -ae "encode=y;codec=aac;bitrate=192k" \
        -in /Users/foo/Movies/in.mov -out /Users/foo/Movies/out.mov

#### Command line sample 2
Using libx264 with yuv420, and crf mode; x264 High profile level 4.1:

    $ movencoder2 -verbose \
        -mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
        -meve "c=libx264;r=30000:1001;o=preset=medium:profile=high" \
        -mex264 "level=4.1:vbv-maxrate=62500:vbv-bufsize=62500:crf=19:keyint=60:min-keyint=6:bframes=3" \
        -ae "encode=y;codec=aac;bitrate=192k" \
        -in /Users/foo/Movies/cam.mov -out /Users/foo/Movies/out.mov

Another form of above example:

    $ movencoder2 -verbose \
        -mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
        -meve "c=libx264;r=30000:1001;o=preset=medium:profile=high\
        :level=4.1:maxrate=62.5M:bufsize=62.5M:crf=19:g=60:keyint_min=6:bf=3"
        -ae "encode=y;codec=aac;bitrate=192k" \
        -in /Users/foo/Movies/in.mov -out /Users/foo/Movies/out.mov

#### Command line sample 3
Using libx264 with yuv420, and abr mode; 1440x1080 16:9 30fps x264 High profile level 4.0 abr 5.0Mbps:

        $ movencoder2 -verbose \
            -mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
            -meve "c=libx264;r=30000:1001;par=4:3;b=5M;o=preset=medium:profile=high" \
            -mex264 "level=4.0:vbv-maxrate=25000:vbv-bufsize=25000:keyint=60:min-keyint=6:bframes=3" \
            -ae "encode=y;codec=aac;bitrate=192k" \
            -in /Users/foo/Movies/in.mov -out /Users/foo/Movies/out.mov

#### Command line sample 4
Using libx264 with yuv420, and abr mode; 720x480 16:9 with c.a. 30fps x264 Main profile level 3.0 abr 2.0Mbps:

        $ movencoder2 -verbose \
            -mevf "format=yuv422p, yadif=0:-1:0, format=yuv420p" \
            -meve "c=libx264;r=30000:1001;par=40:33;b=2M;clean=704:480:4:0;o=preset=medium:profile=main" \
            -mex264 "level=3.0:vbv-maxrate=10000:vbv-bufsize=10000:keyint=60:min-keyint=6:bframes=3" \
            -ae "encode=y;codec=aac;bitrate=128k" \
            -in /Users/foo/Movies/SD16x9.mov -out /Users/foo/Movies/out.mov

---

#### Generic Options
    -verbose
        show some informative details.
    -debug
        set AV_LOG_DEBUG for av_log().
    -dump
        show internal SampleBufferChannel progress.
    -in file
        input movie file path.
    -out file
        output movie file path.
    -ve "args"
        Video Encoder. AVFoundation video encoder options.
    -ae "args"
        Audio Encoder. AVFoundation audio encoder options.
    -co
        Copy Others. Copy non-A/V tracks into output movie.
    -meve "args"
        libavcodec based video encoder string. i.e. ffmpeg -h encoder=libx264
    -mevf "args"
        libavilter based video filter string. i.e. ffmpeg -vf "args"
    -x264 "args"
        libx264 based video encoder string. i.e. x264 -h long
    -x265 "args"
        libx265 based video encoder string. i.e. x265 -h long

#### Arguments (-ve)
    These arguments are for AVFoundation based video encoder.
    every parameters are separated by semi-colon (;).
    e.g. -ve "encode=y;codec=avc1;nclc=y;field=y;bitrate=5M"

    encode=boolean
        transcode via AVFoundation. Should be y/yes.
    codec=string
        fourCC string video encoder. i.e. avc1, hvc1, apcn, apcs, apco, ...
    bitrate=numeric
        video bit rate (i.e. 2.5M, 5M, 10M, 20M, ...)
    field=boolean
        put fild atom into output video sampledescritpion.
    nclc=boolean
        put nclc atom into output video sampledescription.

#### Arguments (-ae)
    These arguments are for AVFoundation based audio encoder.
    every parameters are separated by semi-colon (;).
    e.g. -ae "encode=y;codec=aac;bitrate=192k"

    encode=boolean
        transcode audio using AVFoundation (yes/no)
    codec=string
        fourCC string audio encoder. (lcpm, aac, alac, ...)
    bitrate=numeric
        audio bit rate (i.e. 96k, 128k, 192k, ...)
    depth=numeric
        LPCM bit depth (8, 16, 32)

#### Arguments (-meve)
    These arguments are for libavcodec based video encoder.
    every parameters are separated by semi-colon (;).
    e.g. -meve "c=libx264;r=30000:1001;par=40:33;b=5M;clean=704:480:4:0;o=preset=medium:profile=high:level=4.1"

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
    clean=witdh:height:hOffset:vOffset
        put special clean aperture (clap) atom into output movie. optional.
        NOTE: This does not crop.
        e.g. clean=704,480,4,0
    f=string
        same as -mevf option.
    x264=string
        same as -x264 option.
    x265=string
        same as -x265 option.

#### Arguments (-mevf)
    These arguments are for libavfilter based video filter.
    every parameters are separated by comma (,).
    e.g. -mevf "format=yuv422p,yadif=0:-1:0,format=uyvy422"

    reference: ffmpeg -filters; ffmpeg -h filter=format; ffmpeg -h filter=yadif;

#### Arguments (-mex264)
    These arguments are optional, for libx264 based video encoder.
    NOTE:preset and profile should be -meve "o=preset=xxx:profile=xxx".
    e.g. -mex264 "level=4.1:vbv-maxrate=50000:vbv-bufsize=62500:crf=19:keyint=60:min-keyint=6:bframes=3"

    reference: x264 -h; x264 --longhelp; x264 --fullhelp;

#### Arguments (-mex265)
    These arguments are optional, for libx265 based video encoder.
    NOTE:preset and tune should be -meve "o=preset=xxx:tune=xxx".

    reference: x265 -h; x265 --fullhelp;

---
