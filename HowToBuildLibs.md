# How to build ffmpeg/x264/x265 libraries

## Requirements
- Xcode Command line tool
- MacPorts (See: https://www.macports.org)

## Library/binary separation
- MacPorts: /opt/local/lib, /opt/local/bin
- Manual build: /usr/local/lib, /usr/local/bin
- If you use homebrew you need to take care of conflict.

## Build note
- For manual x265 builds, use build/linux instead of build/xcode.
- Binaries are not contained in dmg file. Build your own binaries/libraries by yourself.
    
## Restart from clean state (optional)
    $ sudo port -fp uninstall installed
    => remove all installed ports first

## Setup pre-built libraries using MacPorts
    $ sudo port -v selfupdate
    $ port list outdated
    $ sudo port upgrade installed
    $ sudo port uninstall inactive
    $
    $ sudo port install yasm nasm cmake pkgconfig
    => install required ports to build x264/x265/ffmpeg
    $ port list installed
    $
    $ ls -l /usr/local/
    $   sudo mkdir -p /usr/local/include
    $   sudo chmod 755 /usr/local/include

## Rebuild 3 linked libraries from source
    $ sudo vi /opt/local/etc/macports/macports.conf
    macosx_deployment_target 12.0
    => Set macosx_deployment_target to 12.0 or so
    $
    $ sudo port -s -f upgrade --force bzip2 xz zlib 
    => Rebuild ports from source using specified macOS version
    $
    $ for item in $(find /opt/local/lib -type f -name '*dylib');do \
      ls -l $item; otool -l $item | grep -nA4 'LC_BUILD_VERSION' | grep -E 'sdk|minos' ;done
    => Verify dylib LC_BUILD_VERSION-minos is as expected

## Clone git repositories
    $ cd yourWorkDir
    $ git clone https://code.videolan.org/videolan/x264.git x264 ;
    $ git clone https://bitbucket.org/multicoreware/x265_git.git x265 ;
    $ git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg ;
    $
    $ ls -l
    total 0
    drwxr-xr-x  37 mycometg3  staff  1184 Oct  4 18:11 ffmpeg
    drwxr-xr-x  28 mycometg3  staff   896 Oct  4 17:56 x264
    drwxr-xr-x  13 mycometg3  staff   416 Oct  4 17:59 x265

## Explicitly set compatible version 
    $ export MACOSX_DEPLOYMENT_TARGET=12.0

## Build/install x264 binary and libs (w/ high bit depth support)
    $ cd yourWorkDir/x264/
    $ NPROC=$(sysctl -n hw.ncpu)
    $ ./configure --enable-static --enable-shared --system-libx264 --bit-depth=all \
      --extra-cflags='-mmacosx-version-min=12.0' --extra-ldflags='-mmacosx-version-min=12.0' 
    $ make -j${NPROC}
    $ ls -l lib*.a lib*.dylib
    $ sudo make install
    $
    $ otool -L /usr/local/lib/libx264.dylib /usr/local/bin/x264 | grep -iv system
    => Verify dylib path is absolute path
    $ for item in /usr/local/lib/libx264.{a,dylib} /usr/local/bin/x264 ;\
      do echo $item; otool -l $item | grep -nA4 'LC_BUILD_VERSION' | grep -E 'minos|sdk'; done
    => Verify LC_BUILD_VERSION-minos is as expected

## Build/install x265 binary and libs (w/ high bit depth support)
    $ cd yourWorkDir; cd x265/build/linux/ ; pwd
    $ NPROC=$(sysctl -n hw.ncpu)
    $ BUILD_DIR=$(pwd)
    $ mkdir -p "$BUILD_DIR/8bit" "$BUILD_DIR/10bit" "$BUILD_DIR/12bit" && ls -l
    $ 
    $ echo "=== Building 12bit (internal, static only) ==="
    $ cd "$BUILD_DIR/12bit"
    $ cmake ../../../source \
      -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
      -DHIGH_BIT_DEPTH=ON -DMAIN12=ON \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 
    $ grep -E "ENABLE_CLI|ENABLE_SHARED|EXPORT_C_API|HIGH_BIT_DEPTH|MAIN12" CMakeCache.txt
    $ make -j${NPROC}
    $ ls -l  "$BUILD_DIR/12bit/libx265.a"
    $ ln -sf "$BUILD_DIR/12bit/libx265.a" "$BUILD_DIR/8bit/libx265_main12.a"
    $ ls -l  "$BUILD_DIR/12bit/libx265.a" "$BUILD_DIR/8bit/libx265_main12.a"
    $ 
    $ echo "=== Building 10bit (internal, static only) ==="
    $ cd "$BUILD_DIR/10bit"
    $ cmake ../../../source \
      -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF \
      -DHIGH_BIT_DEPTH=ON -DMAIN12=OFF \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 
    $ grep -E "ENABLE_CLI|ENABLE_SHARED|EXPORT_C_API|HIGH_BIT_DEPTH|MAIN12" CMakeCache.txt
    $ make -j${NPROC}
    $ ls -l  "$BUILD_DIR/10bit/libx265.a"
    $ ln -sf "$BUILD_DIR/10bit/libx265.a" "$BUILD_DIR/8bit/libx265_main10.a"
    $ ls -l  "$BUILD_DIR/10bit/libx265.a" "$BUILD_DIR/8bit/libx265_main10.a"
    $ 
    $ echo "=== Building 8bit (with C API, shared + static) ==="
    $ cd "$BUILD_DIR/8bit"
    $ cmake ../../../source \
      -DEXPORT_C_API=ON -DENABLE_SHARED=ON -DENABLE_CLI=ON \
      -DCMAKE_INSTALL_NAME_DIR="/usr/local/lib" \
      -DEXTRA_LINK_FLAGS=-L. \
      -DEXTRA_LIB="x265_main10.a;x265_main12.a" \
      -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 
    $ grep -E "ENABLE_CLI|ENABLE_SHARED|EXPORT_C_API|HIGH_BIT_DEPTH|MAIN12" CMakeCache.txt
    $ make -j${NPROC}
    $ ls -l lib*.a lib*.dylib x265
    $ sudo make install
    $ 
    $ otool -L /usr/local/lib/libx265.dylib /usr/local/bin/x265 | grep -iv system
    => Verify dylib path is absolute path
    $ for item in /usr/local/lib/libx265.{a,dylib} /usr/local/bin/x265 ;\
      do echo $item; otool -l $item | grep -nA4 'LC_BUILD_VERSION' | grep -E 'minos|sdk'; done
    => Verify LC_BUILD_VERSION-minos is as expected

## Build/install ffmpeg binary and libs
    $ cd yourWorkDir/ffmpeg/
    $ NPROC=$(sysctl -n hw.ncpu)
    $ PKG_CONFIG_PATH="/usr/local/lib/pkgconfig" ./configure \
      --enable-gpl --enable-version3 --enable-shared --enable-libx264 --enable-libx265 \
      --extra-cflags='-mmacosx-version-min=12.0' --extra-ldflags='-mmacosx-version-min=12.0'
    $ make -j${NPROC}
    $ ls -l */lib*.a */lib*.dylib ffmpeg ffprobe
    $ sudo make install
    $ 
    $ otool -L /usr/local/lib/lib{av,sw}*.dylib /usr/local/bin/ff* | grep -iv system
    => Verify dylib path is absolute path
    $ for item in /usr/local/lib/lib{av,sw}*.{a,dylib} /usr/local/bin/ff* ;\
      do echo $item; otool -l $item | grep -nA4 'LC_BUILD_VERSION' | grep -E 'minos|sdk'; done
    => Verify LC_BUILD_VERSION-minos is as expected

## Verify installed files
    $ ls -l /usr/local/lib/*.a
    $ ls -l /usr/local/lib/*.dylib
    $ ls -l /usr/local/include/*.h
    $ ls -l /usr/local/include/*/*.h
    $ ls -l /usr/local/lib/pkgconfig/*.pc

## Verify binaries
    $ which x264 x265 ffmpeg
    /usr/local/bin/x264
    /usr/local/bin/x265
    /usr/local/bin/ffmpeg
    $ 
    $ x264 --version
    x264 0.165.3223 0480cb0
    (libswscale 9.3.100)
    (libavformat 62.6.100)
    built on Oct  5 2025, clang: 17.0.0 (clang-1700.3.19.1)
    x264 configuration: --chroma-format=all
    libx264 configuration: --chroma-format=all
    x264 license: GPL version 2 or later
    libswscale/libavformat license: GPL version 3 or later
    $ 
    $ x265 --version
    x265 [info]: HEVC encoder version 4.1+191-10f529eaa
    x265 [info]: build info [Mac OS X][clang 17.0.0][64 bit] 8bit+10bit+12bit
    x265 [info]: using cpu capabilities: NEON Neon_DotProd Neon_I8MM
    $ 
    $ ffmpeg -version
    ffmpeg version N-121326-g8fad52bd57 Copyright (c) 2000-2025 the FFmpeg developers
    built with Apple clang version 17.0.0 (clang-1700.3.19.1)
    configuration: --enable-gpl --enable-version3 --enable-shared --enable-libx264 --enable-libx265 --extra-cflags='-mmacosx-version-min=12.0' --extra-ldflags='-mmacosx-version-min=12.0'
    libavutil      60. 13.100 / 60. 13.100
    libavcodec     62. 16.100 / 62. 16.100
    libavformat    62.  6.100 / 62.  6.100
    libavdevice    62.  2.100 / 62.  2.100
    libavfilter    11.  9.100 / 11.  9.100
    libswscale      9.  3.100 /  9.  3.100
    libswresample   6.  2.100 /  6.  2.100

    Exiting with exit code 0
    $ 
