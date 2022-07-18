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
    $ git clone https://github.com/mirror/x264.git x264 ;
    $ git clone https://bitbucket.org/multicoreware/x265_git.git x265 ;
    $ git clone https://github.com/FFmpeg/FFmpeg ffmpeg ;
    $
    $ ls -l
    total 0
    drwxr-xr-x  37 username  staff  1258  7 12 10:01 ffmpeg
    drwxr-xr-x  27 username  staff   918  7 12 09:57 x264
    drwxr-xr-x   9 username  staff   306  7 12 09:57 x265
    $
#### Build/install x264 binary and libs
    $ cd yourWorkDir/x264/
    $ ./configure --enable-static --enable-shared --disable-avs --disable-opencl --extra-cflags='-mmacosx-version-min=10.15' --extra-ldflags='-mmacosx-version-min=10.15'
    $ make
    => Verify lib*.a and lib*.*.dylib
    $ otool -l libx264.a | grep -A4 'LC_VERSION_MIN_MACOSX'
    => Check build target as expected
    $ sudo make install
#### Build/install x265 binary and libs
    $ cd yourWorkDir/x265/build/linux/
    $ ./make-Makefiles.bash
    => Set CMAKE_OSX_DEPLOYMENT_TARGET = 10.15
    => c(configure) => e(exit) => g(generate)
    $ make
    => Verify lib*.a and lib*.*.dylib
    $ otool -l libx264.a | grep -A4 'LC_VERSION_MIN_MACOSX'
    => Check build target as expected
    $ sudo make install
#### Build/install ffmpeg binary and libs
    $ cd yourWorkDir/ffmpeg/
    $ PKG_CONFIG_PATH="/usr/local/lib/pkgconfig" ./configure \
    >  --enable-gpl --enable-version3 --enable-shared --enable-libx264 --enable-libx265 \
    >  --extra-cflags='-mmacosx-version-min=10.15' --extra-ldflags='-mmacosx-version-min=10.15'
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
    x264 0.164.3095 baee400
    (libswscale 6.1.102)
    (libavformat 59.10.100)
    built on Jul 17 2022, clang: 13.1.6 (clang-1316.0.21.2.5)
    x264 configuration: --chroma-format=all
    libx264 configuration: --chroma-format=all
    x264 license: GPL version 2 or later
    libswscale/libavformat license: GPL version 3 or later
    $
    $ x265 --version
    x265 [info]: HEVC encoder version 3.5+38-20255e6f0
    x265 [info]: build info [Mac OS X][clang 13.1.6][64 bit] 8bit
    x265 [info]: using cpu capabilities: MMX2 SSE2Fast LZCNT SSSE3 SSE4.2 AVX FMA3 BMI2 AVX2
    $
    $ ffmpeg -version
    ffmpeg version N-107417-g940169b8aa Copyright (c) 2000-2022 the FFmpeg developers
    built with Apple clang version 13.1.6 (clang-1316.0.21.2.5)
    configuration: --enable-gpl --enable-version3 --enable-shared --enable-libx264 --enable-libx265 --extra-cflags='-mmacosx-version-min=10.15' --extra-ldflags='-mmacosx-version-min=10.15'
    libavutil      57. 29.100 / 57. 29.100
    libavcodec     59. 39.100 / 59. 39.100
    libavformat    59. 29.100 / 59. 29.100
    libavdevice    59.  8.100 / 59.  8.100
    libavfilter     8. 45.100 /  8. 45.100
    libswscale      6.  8.100 /  6.  8.100
    libswresample   4.  8.100 /  4.  8.100
    libpostproc    56.  7.100 / 56.  7.100
    $
#### Note
    Binaries are not contained in dmg file.
    You need to build your own binaries/libraries by yourself.
