## How to build ffmpeg/x264/x265 libraries

#### Requirements
- Xcode Command line tool
- MacPorts (See: https://www.macports.org)

#### Setup build utilities using MacPorts
    $ sudo port -v selfupdate
    $   sudo port install yasm
    $   sudo port install nasm
    $   sudo port install cmake
    $   sudo port install pkgconfig
    $ port list outdated
    $   sudo port upgrade installed
    $   sudo port uninstall inactive
    $ port list installed
    $
    $ ls -l /usr/local/
    $   sudo mkdir -p /usr/local/include
    $   sudo chmod 755 /usr/local/include
    $
#### Clone git repositories
    $ cd yourWorkDir
    $ git clone git://github.com/mirror/x264
    $ git clone git://github.com/videolan/x265
    $ git clone git://github.com/FFmpeg/FFmpeg
    $
    $ ls -l
    total 0
    drwxr-xr-x  37 username  staff  1258  7 12 10:01 ffmpeg
    drwxr-xr-x  27 username  staff   918  7 12 09:57 x264
    drwxr-xr-x   9 username  staff   306  7 12 09:57 x265
    $
#### Build/install x264 binary and libs
    $ cd yourWorkDir/x264/
    $ ./configure --enable-static --enable-shared --disable-avs --disable-opencl --extra-cflags='-mmacosx-version-min=10.13' --extra-ldflags='-mmacosx-version-min=10.13'
    $ make
    => Verify lib*.a and lib*.*.dylib
    $ otool -l libx264.a | grep -A4 'LC_VERSION_MIN_MACOSX'
    => Check build target as expected
    $ sudo make install
#### Build/install x265 binary and libs
    $ cd yourWorkDir/x265/build/linux/
    $ ./make-Makefiles.bash
    => Set CMAKE_OSX_DEPLOYMENT_TARGET = 10.13
    => c(configure) => e(exit) => g(generate)
    $ make
    => Verify lib*.a and lib*.*.dylib
    $ otool -l libx264.a | grep -A4 'LC_VERSION_MIN_MACOSX'
    => Check build target as expected
    $ sudo make install
#### Build/install ffmpeg binary and libs
    $ cd yourWorkDir/ffmpeg/
    $ PKG_CONFIG_PATH="/usr/local/lib/pkgconfig" ./configure \
    >  --enable-gpl --enable-version3 --enable-nonfree --enable-shared --enable-libx264 --enable-libx265 \
    >  --extra-cflags='-mmacosx-version-min=10.13' --extra-ldflags='-mmacosx-version-min=10.13'
    $ make
    => Verify lib*.a and lib*.*.dylib
    $ otool -l libxxxx.a | grep -A4 'LC_VERSION_MIN_MACOSX'
    => Check build target as expected
    $ sudo make install
#### Verify installed files
    $ ls -l /usr/local/lib/*.a
    $ ls -l /usr/local/lib/*.dylib
    $ ls -l /usr/local/include/*.h
    $ ls -l /usr/local/include/*/*.h
    $ ls -l /usr/local/lib/pkgconfig/*.pc
#### Verify binaries
    $ x264 --version
    x264 0.161.3015 4c2aafd
    (libswscale 5.6.100)
    (libavformat 58.35.102)
    built on Jul 12 2020, gcc: 4.2.1 Compatible Apple LLVM 11.0.3 (clang-1103.0.32.29)
    x264 configuration: --chroma-format=all
    libx264 configuration: --chroma-format=all
    x264 license: GPL version 2 or later
    libswscale/libavformat license: nonfree and unredistributable
    WARNING: This binary is unredistributable!
    $
    $ x265 --version
    x265 [info]: HEVC encoder version 3.4+12-gf7967350c
    x265 [info]: build info [Mac OS X][clang 11.0.3][64 bit] 8bit
    x265 [info]: using cpu capabilities: MMX2 SSE2Fast LZCNT SSSE3 SSE4.2 AVX FMA3 BMI2 AVX2
    $
    $ ffmpeg -version
    ffmpeg version N-98463-g3205ed31a7 Copyright (c) 2000-2020 the FFmpeg developers
    built with Apple clang version 11.0.3 (clang-1103.0.32.29)
    configuration: --enable-gpl --enable-version3 --enable-nonfree --enable-shared --enable-libx264 --enable-libx265 --extra-cflags='-mmacosx-version-min=10.13' --extra-ldflags='-mmacosx-version-min=10.13'
    libavutil      56. 55.100 / 56. 55.100
    libavcodec     58. 95.100 / 58. 95.100
    libavformat    58. 48.100 / 58. 48.100
    libavdevice    58. 11.101 / 58. 11.101
    libavfilter     7. 87.100 /  7. 87.100
    libswscale      5.  8.100 /  5.  8.100
    libswresample   3.  8.100 /  3.  8.100
    libpostproc    55.  8.100 / 55.  8.100
    $
#### Note
    As you can see above, these built binaries are non-distributable (non-free).
    You need to build your own binaries/libraries by yourself.
