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
    drwxr-xr-x  45 takashi  staff  1440 10 29 22:18 ffmpeg
    drwxr-xr-x  40 takashi  staff  1280 10 29 21:55 x264
    drwxr-xr-x  13 takashi  staff   416 10 29 15:08 x265
    $
#### Add some workaround for linker known issue (Xcode 15.0) 
    $ export MACOSX_DEPLOYMENT_TARGET=12
    $ export OTHER_LDFLAGS=-Wl,-ld_classic
#### Build/install x264 binary and libs
    $ cd yourWorkDir/x264/
    $ ./configure --enable-static --enable-shared --system-libx264 \
      --extra-cflags='-mmacosx-version-min=12' \
      --extra-ldflags='-mmacosx-version-min=12 -Wl,-ld_classic' 
    $ make
    => Verify lib*.a and lib*.dylib
    $ otool -L lib*.dylib
    => Verify dylib path is absolute path
    $ sudo make install
#### Build/install x265 binary and libs
    $ cd yourWorkDir/x265/build/linux/
    $ vi source/CMakeLists.txt
    => Update cmake_minimum_required() to VERSION 3.24.4 or so - set actual cmake version here
    $ ./make-Makefiles.bash
    => c(configure) => e(exit) => g(generate)
    $ vi CMakeCache.txt
    => CMAKE_BUILD_WITH_INSTALL_NAME_DIR:BOOL=ON         # use /usr/local
    => CMAKE_EXE_LINKER_FLAGS = -Wl,-ld_classic          # workaround for linker issue
    => CMAKE_INSTALL_NAME_DIR:PATH=/usr/local/lib        # use /usr/local/lib
    => CMAKE_INSTALL_PREFIX:PATH=/usr/local              # use /usr/local
    => CMAKE_OSX_DEPLOYMENT_TARGET:STRING=12             # workaround for linker issue
    => CMAKE_SHARED_LINKER_FLAGS:STRING=-Wl,-ld_classic  # workaround for linker issue
    $ ./make-Makefiles.bash
    => t(toggle advanced mode) - verify settings as expected
    => c(configure) => e(exit) => g(generate)
    $ make
    => Verify lib*.a and lib*.dylib
    $ otool -L lib*dylib
    => Verify dylib path is absolute path
    $ sudo make install
#### Build/install ffmpeg binary and libs
    $ cd yourWorkDir/ffmpeg/
    $ PKG_CONFIG_PATH="/usr/local/lib/pkgconfig" ./configure \
      --enable-gpl --enable-version3 --enable-shared --enable-libx264 --enable-libx265 \
      --extra-cflags='-mmacosx-version-min=12' \
      --extra-ldflags='-mmacosx-version-min=12 -Wl,-ld_classic'
    $ make
    => Verify lib*.a and lib*.dylib
    $ otool -L */lib*.a */lib*.dylib
    => Verify dylib path is absolute path
    $ sudo make install
#### Verify installed files
    $ ls -l /usr/local/lib/*.a
    $ ls -l /usr/local/lib/*.dylib
    $ ls -l /usr/local/include/*.h
    $ ls -l /usr/local/include/*/*.h
    $ ls -l /usr/local/lib/pkgconfig/*.pc
#### Verify binaries
    $ x264 --version
    x264 0.164.3106 eaa68fa
    built on Oct 29 2023, clang: 15.0.0 (clang-1500.0.40.1)
    x264 configuration: --chroma-format=all
    libx264 configuration: --chroma-format=all
    x264 license: GPL version 2 or later
    $
    $ x265 --version
    x265 [info]: HEVC encoder version 3.5+110-8ee01d45b
    x265 [info]: build info [Mac OS X][clang 15.0.0][64 bit] 8bit
    x265 [info]: using cpu capabilities: MMX2 SSE2Fast LZCNT SSSE3 SSE4.2 AVX FMA3 BMI2 AVX2
    $
    $ ffmpeg -version
    ffmpeg version N-112534-ge5f774268a Copyright (c) 2000-2023 the FFmpeg developers
    built with Apple clang version 15.0.0 (clang-1500.0.40.1)
    configuration: --enable-gpl --enable-version3 --enable-shared --enable-libx264 --enable-libx265 --extra-cflags='-mmacosx-version-min=12' --extra-ldflags='-mmacosx-version-min=12 -Wl,-ld_classic'
    libavutil      58. 28.100 / 58. 28.100
    libavcodec     60. 30.102 / 60. 30.102
    libavformat    60. 15.101 / 60. 15.101
    libavdevice    60.  2.101 / 60.  2.101
    libavfilter     9. 11.100 /  9. 11.100
    libswscale      7.  4.100 /  7.  4.100
    libswresample   4. 11.100 /  4. 11.100
    libpostproc    57.  2.100 / 57.  2.100
    $
#### Note
    Binaries are not contained in dmg file.
    You need to build your own binaries/libraries by yourself.
