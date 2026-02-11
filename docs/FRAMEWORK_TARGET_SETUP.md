# Framework Target Setup

**Last Updated:** February 2026

## Overview

This document describes the MovEncoder2Framework target implementation, which enables the project to be distributed as a macOS framework alongside the existing command-line tool.

## Project Structure

### Targets

The project contains three targets, all building for arm64 architecture:

1. **movencoder2** - Command-line tool (executable)
2. **MovEncoder2Framework** - Framework target (dylib)
3. **movencoder2Tests** - Unit test bundle

### Directory Layout

```
movencoder2/                      # Shared source code
  Config/                         # Internal: Configuration
  Core/                           # Internal: Core logic
  Pipeline/                       # Internal: Pipeline components
  IO/                            # Internal: Input/Output
  Utils/                         # Internal: Utilities
  Public/                        # Public API headers
    MovEncoder2.h                # Umbrella header
    METranscoder.h               # Main transcoding API
    MEVideoEncoderConfig.h       # Configuration API
    METypes.h                    # Public type definitions
  main.m                         # CLI tool entry point (excluded from framework)

MovEncoder2Framework/            # Framework resources
  Info.plist                     # Framework bundle info
```

### Build Products

```
build/Debug/
├── movencoder2                    # CLI tool executable (arm64)
├── MovEncoder2.framework/         # Framework bundle
│   ├── Headers/                   # 4 public headers
│   │   ├── MovEncoder2.h
│   │   ├── METranscoder.h
│   │   ├── MEVideoEncoderConfig.h
│   │   └── METypes.h
│   ├── Modules/
│   │   └── module.modulemap       # Auto-generated module map
│   ├── MovEncoder2                # Framework binary (arm64)
│   └── Resources/
│       └── Info.plist
└── movencoder2Tests.xctest        # Test bundle
```

## Target Configuration

### MovEncoder2Framework (Framework)

- **Product Name**: MovEncoder2.framework
- **Architecture**: arm64 only
- **Deployment Target**: macOS 12.0
- **Source Files**: All .m files except main.m (19 files)
- **Public Headers**: 4 headers from Public/ directory
- **System Frameworks**: Foundation, AVFoundation, CoreMedia, CoreVideo, VideoToolbox, CoreAudio
- **External Libraries**: FFmpeg (libavcodec, libavformat, libavutil, etc.), libx264, libx265
- **Module Support**: Enabled (DEFINES_MODULE = YES)
- **Headers Path**: $(CONTENTS_FOLDER_PATH)/Headers

### movencoder2 (CLI Tool)

- **Product Name**: movencoder2
- **Architecture**: arm64 only
- **Deployment Target**: macOS 12.0
- **Source Files**: All .m files including main.m
- **Unchanged**: Original configuration preserved

### movencoder2Tests (Unit Tests)

- **Product Name**: movencoder2Tests.xctest
- **Architecture**: arm64 only (updated for consistency)
- **Deployment Target**: macOS 12.0
- **Test Files**: MEPipelineIntegrationTests.m, MEVideoEncoderConfigTests.m

## Architecture Constraint

All targets are configured to build for **arm64 only**. This is due to external library dependencies (FFmpeg, x264, x265) being available only for arm64 architecture in the development environment.

To build Universal Binaries (arm64 + x86_64), x86_64 versions of all external libraries must be available.

## Build Commands

### Build Framework
```bash
xcodebuild -project movencoder2.xcodeproj \
           -target MovEncoder2Framework \
           -configuration Debug \
           -arch arm64 \
           build
```

### Build CLI Tool
```bash
xcodebuild -project movencoder2.xcodeproj \
           -target movencoder2 \
           -configuration Debug \
           -arch arm64 \
           build
```

### Build Tests
```bash
xcodebuild -project movencoder2.xcodeproj \
           -target movencoder2Tests \
           -configuration Debug \
           -arch arm64 \
           build
```

## Using the Framework

### Compilation

```bash
clang -arch arm64 -fmodules \
      -framework Foundation \
      -framework MovEncoder2 \
      -F build/Debug \
      -Wl,-rpath,build/Debug \
      myapp.m -o myapp
```

### Code Example

```objective-c
#import <MovEncoder2/MovEncoder2.h>

// Create configuration
MEVideoEncoderConfig *config = [[MEVideoEncoderConfig alloc] init];
[config setCodec:MEVideoCodecH264];

// Create transcoder
NSURL *inputURL = [NSURL fileURLWithPath:@"/path/to/input.mov"];
NSURL *outputURL = [NSURL fileURLWithPath:@"/path/to/output.mov"];

METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL 
                                                         output:outputURL];
[transcoder setConfig:config];

// Set progress callback
[transcoder setProgressBlock:^(double progress) {
    NSLog(@"Progress: %.1f%%", progress * 100.0);
}];

// Start transcoding
BOOL success = [transcoder start];
if (success) {
    NSLog(@"Transcoding completed successfully");
}
```

## Scheme Configuration

All schemes are configured as shared schemes (in xcshareddata/) for team development:

- **movencoder2** - CLI tool scheme
- **MovEncoder2Framework** - Framework scheme
- **movencoder2Tests** - Test scheme

No user-specific schemes exist in xcuserdata/, ensuring consistency across the team.

## Naming Convention

To avoid case-insensitivity issues on macOS file systems:

- **Target Name**: MovEncoder2Framework (matches directory name)
- **Product Name**: MovEncoder2.framework (clean framework name)
- **Resource Directory**: MovEncoder2Framework/ (distinct from source directory)
- **Source Directory**: movencoder2/ (lowercase, for source code)

This naming strategy ensures:
- No conflicts with case-insensitive file systems
- Consistency between target and directory names
- Clear distinction between source and resources

## Dependencies

### System Frameworks
- Foundation.framework
- AVFoundation.framework
- CoreMedia.framework
- CoreVideo.framework
- VideoToolbox.framework
- CoreAudio.framework

### External Libraries
- FFmpeg libraries (libavcodec, libavformat, libavutil, libswscale, libswresample, libavfilter, libavdevice)
- libx264
- libx265
- System libraries (libbz2, liblzma, libz)

**Note**: External libraries must be present at runtime. The framework uses dynamic linking and does not embed these libraries.

## Distribution Considerations

### Requirements for End Users
1. macOS 12.0 or later
2. arm64 Mac (Apple Silicon)
3. External libraries installed (FFmpeg, x264, x265) in /usr/local/lib or /opt/local/lib

### Future Enhancements
- Swift Package Manager support
- CocoaPods / Carthage support
- XCFramework for multi-architecture support
- Static linking of external libraries for standalone distribution

## Verification

All targets build successfully:
- ✅ movencoder2 (CLI Tool)
- ✅ MovEncoder2Framework (Framework)
- ✅ movencoder2Tests (Unit Tests)

Framework structure conforms to Apple's standard framework layout with:
- Proper Headers/ directory containing public headers
- Modules/ directory with auto-generated module map
- Standard versioned framework structure (Versions/A/)

## References

- [Apple Framework Programming Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPFrameworks/)
- [Creating Custom Frameworks](https://developer.apple.com/documentation/xcode/creating-a-custom-framework)
- [API_GUIDELINES.md](API_GUIDELINES.md) - Public API design guidelines
- [ARCHITECTURE.md](ARCHITECTURE.md) - Overall project architecture
