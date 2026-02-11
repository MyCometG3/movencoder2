# movencoder2 API Guidelines

**Last Updated:** February 2026

---

## Overview

This document describes the public API surface of movencoder2 and provides guidelines for using the library. The movencoder2 API is now separated into **public** and **internal** interfaces to provide a stable, well-defined API for framework consumers.

---

## Public API Surface

The public API consists of headers located in the `movencoder2/Public/` directory. These headers are stable and suitable for external use.

### Umbrella Header

```objective-c
#import <MovEncoder2/MovEncoder2.h>
```

The umbrella header (`MovEncoder2.h`) includes all public APIs and is the recommended way to import the framework.

### Public Headers

#### 1. METranscoder.h

**Purpose:** Main transcoding controller

The `METranscoder` class is the primary entry point for all transcoding operations. It provides a high-level facade over the internal transcoding pipeline.

**Key Classes:**
- `METranscoder` - Main transcoding controller

**Key Types:**
- `progress_block_t` - Progress callback block type

**Configuration Keys:**
- `kLPCMDepthKey` - PCM bit depth (NSNumber of int)
- `kAudioKbpsKey` - Audio bitrate in kbps (NSNumber of float)
- `kVideoKbpsKey` - Video bitrate in kbps (NSNumber of float)
- `kCopyFieldKey` - Preserve field information (NSNumber of BOOL)
- `kCopyNCLCKey` - Preserve color information (NSNumber of BOOL)
- `kCopyOtherMediaKey` - Copy other media tracks (NSNumber of BOOL)
- `kVideoEncodeKey` - Enable video encoding (NSNumber of BOOL)
- `kAudioEncodeKey` - Enable audio encoding (NSNumber of BOOL)
- `kVideoCodecKey` - Video codec identifier (NSString of OSType)
- `kAudioCodecKey` - Audio codec identifier (NSString of OSType)
- `kAudioChannelLayoutTagKey` - Audio channel layout (NSNumber of uint32_t)
- `kAudioVolumeKey` - Audio volume in dB (NSNumber of float)

#### 2. MEVideoEncoderConfig.h

**Purpose:** Type-safe video encoder configuration

Provides a type-safe wrapper over the legacy dictionary-based configuration system.

**Key Classes:**
- `MEVideoEncoderConfig` - Immutable encoder configuration object

**Key Properties:**
- `codecKind` - Video codec type (MEVideoCodecKind enum)
- `frameRate` - Target frame rate (CMTime)
- `bitRate` - Target bitrate in bits/second
- `declaredSize` - Video dimensions
- `pixelAspect` - Pixel aspect ratio
- `codecOptions` - Codec-specific options
- `x264Params` / `x265Params` - Codec-specific parameter strings

#### 3. METypes.h

**Purpose:** Public type definitions

**Key Types:**
- `MEVideoCodecKind` - Enum for video codec types
  - `MEVideoCodecKindX264` - H.264 via libx264
  - `MEVideoCodecKindX265` - H.265 via libx265
  - `MEVideoCodecKindOther` - Other codecs

**Key Functions:**
- `MEVideoCodecKindFromName()` - Convert codec name to enum value

#### 4. Progress Callback Constants

These constants are used in progress callback dictionaries:

- `kProgressMediaTypeKey` - Media type ("vide", "soun", etc.)
- `kProgressTagKey` - Track/channel identifier
- `kProgressTrackIDKey` - Track ID (CMPersistentTrackID)
- `kProgressPTSKey` - Presentation timestamp in seconds
- `kProgressDTSKey` - Decode timestamp in seconds
- `kProgressPercentKey` - Progress percentage (0.0 - 100.0)
- `kProgressCountKey` - Sample count

---

## Usage Examples

### Basic Transcoding

```objective-c
#import <MovEncoder2/MovEncoder2.h>

// Create transcoder
NSURL *inputURL = [NSURL fileURLWithPath:@"/path/to/input.mov"];
NSURL *outputURL = [NSURL fileURLWithPath:@"/path/to/output.mov"];

METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL
                                                        output:outputURL];

// Configure parameters
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"avc1",
    kVideoKbpsKey: @5000,
    kAudioEncodeKey: @YES,
    kAudioCodecKey: @"aac ",
    kAudioKbpsKey: @256
} mutableCopy];

// Start transcoding asynchronously
[transcoder startAsync];
```

### With Progress Monitoring

```objective-c
// Set progress callback
transcoder.progressCallback = ^(NSDictionary *info) {
    NSNumber *percent = info[kProgressPercentKey];
    NSString *mediaType = info[kProgressMediaTypeKey];

    NSLog(@"Progress [%@]: %.1f%%", mediaType, percent.floatValue);
};

// Set completion callback
transcoder.completionCallback = ^{
    if (transcoder.finalSuccess) {
        NSLog(@"Transcoding completed successfully");
    } else {
        NSLog(@"Transcoding failed: %@", transcoder.finalError);
    }
};

[transcoder startAsync];
```

### Using Type-Safe Configuration

```objective-c
// Legacy configuration dictionary
NSDictionary *legacyConfig = @{
    @"c": @"libx264",
    @"r": @"30000:1001",
    @"b": @"5M",
    @"o": @"preset=medium:profile=high:level=4.1"
};

// Convert to type-safe config
NSError *error = nil;
MEVideoEncoderConfig *config = [MEVideoEncoderConfig configFromLegacyDictionary:legacyConfig
                                                                           error:&error];

if (config) {
    NSLog(@"Codec: %lu", (unsigned long)config.codecKind);
    NSLog(@"Frame rate: %f fps", CMTimeGetSeconds(config.frameRate));
    NSLog(@"Bitrate: %ld bps", (long)config.bitRate);
}
```

### Cancellation

```objective-c
// Cancel ongoing transcoding
[transcoder cancelAsync];

// Check cancellation status
if (transcoder.cancelled) {
    NSLog(@"Transcoding was cancelled");
}
```

---

## Internal APIs

Headers **not** in the `Public/` directory are considered internal implementation details. These include:

### Core Layer (Internal)
- `MEManager.h` - Video encoding pipeline manager
- `MEAudioConverter.h` - Audio processing coordinator
- `METranscoder+Internal.h` - Private METranscoder extensions

### Pipeline Layer (Internal)
- `MEEncoderPipeline.h` - Video encoder abstraction
- `MEFilterPipeline.h` - Video filter graph management
- `MESampleBufferFactory.h` - Sample buffer creation

### IO Layer (Internal)
- `MEInput.h` - Asset reader abstraction
- `MEOutput.h` - Asset writer abstraction
- `SBChannel.h` - Channel coordination

### Utils Layer (Internal)
- `MECommon.h` - Common definitions
- `MEUtils.h` - Video format utilities
- `MESecureLogging.h` - Logging infrastructure
- `MEProgressUtil.h` - Progress calculations
- `MEErrorFormatter.h` - Error formatting
- `parseUtil.h` - Parameter parsing
- `monitorUtil.h` - Signal monitoring

**Important:** Internal APIs may change without notice and should not be used directly by framework consumers.

---

## API Stability Guarantees

### Public API
- **Stability:** Backward compatible changes only
- **Deprecation:** Minimum 1 major version notice before removal
- **Documentation:** Fully documented in headers

### Internal API
- **Stability:** No guarantees - may change at any time
- **Visibility:** Clearly marked with `@internal` documentation
- **Usage:** For internal library use only

---

## Framework Integration

### Xcode Project

When integrating as a framework:

1. Add movencoder2 as a framework dependency
2. Set the framework header search path to include `Public/`
3. Import via `#import <MovEncoder2/MovEncoder2.h>`

### Future: Swift Package Manager

The public API structure is designed to support future Swift Package Manager integration:

```swift
// Future SPM support (planned)
import MovEncoder2

let transcoder = METranscoder(input: inputURL, output: outputURL)
// ...
```

### Future: CocoaPods

```ruby
# Future CocoaPods support (planned)
pod 'MovEncoder2', '~> 1.0'
```

---

## Migration from Internal APIs

If you are currently using internal APIs directly, here's how to migrate:

### MEManager → METranscoder

**Before (Internal API):**
```objective-c
MEManager *manager = [[MEManager alloc] init];
// Configure manager...
```

**After (Public API):**
```objective-c
METranscoder *transcoder = [[METranscoder alloc] initWithInput:input output:output];
// Use transcoder's public interface
```

### Direct Progress Calculation → Progress Callbacks

**Before (Internal API):**
```objective-c
#import "MEProgressUtil.h"
float percent = [MEProgressUtil progressPercentForSampleBuffer:buffer start:start end:end];
```

**After (Public API):**
```objective-c
transcoder.progressCallback = ^(NSDictionary *info) {
    NSNumber *percent = info[kProgressPercentKey];
    // Use percent...
};
```

---

## Best Practices

1. **Always use the umbrella header** (`MovEncoder2.h`) instead of importing individual headers
2. **Don't import internal headers** - they are not part of the stable API
3. **Use type-safe configuration** when possible (`MEVideoEncoderConfig`)
4. **Set callbacks before starting** transcoding operations
5. **Check error status** in completion callbacks
6. **Handle cancellation** gracefully in your application

---

## Support & Feedback

- **Issues:** Report bugs and feature requests via GitHub Issues
- **Documentation:** See README.md and inline header documentation
- **License:** GPL-2.0-or-later (see COPYING.txt)

---

## Version History

### February 2026
- Documentation updates for refactored utility helpers
- Internal API references refreshed

### December 2025
- Initial public API formalization
- Public/internal API separation
- Umbrella header (MovEncoder2.h)
- API documentation and guidelines
