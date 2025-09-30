# Developer Quick Reference

**Version:** 1.0  
**Last Updated:** December 2025

---

## Quick Start

### Building the Project

```bash
# 1. Install dependencies (see HowToBuildLibs.md)
$ sudo port install yasm nasm cmake pkgconfig

# 2. Build external libraries (FFmpeg, x264, x265)
# Follow instructions in HowToBuildLibs.md

# 3. Open in Xcode
$ open movencoder2.xcodeproj

# 4. Build (⌘B)
# Product will be in DerivedData
```

### Running Tests

```bash
# In Xcode: ⌘U (Product > Test)

# Or via xcodebuild:
$ xcodebuild test -scheme movencoder2 -destination 'platform=macOS'
```

### Basic Usage

```bash
# Simple H.264 transcode
$ ./movencoder2 -i input.mov -o output.mov --meve c=libx264:b=5M:r=30000/1001

# H.265 transcode with audio
$ ./movencoder2 -i input.mov -o output.mov \
    --meve c=libx265:b=8M:r=24:1 \
    --meae on:kbps=192
```

---

## Module Quick Reference

### Config Layer

**METypes.h**
```objective-c
typedef NS_ENUM(NSUInteger, MEVideoCodecKind) {
    MEVideoCodecKindX264,
    MEVideoCodecKindX265,
    MEVideoCodecKindOther
};
```

**MEVideoEncoderConfig**
```objective-c
// Create from legacy dictionary
MEVideoEncoderConfig *config = 
    [MEVideoEncoderConfig configFromLegacyDictionary:dict error:&error];

// Access properties (all readonly)
MEVideoCodecKind codec = config.codecKind;
NSInteger bitrate = config.bitRate;
CMTime frameRate = config.frameRate;
NSString *x264Params = config.x264Params;
NSArray<NSString*> *issues = config.issues; // Validation issues
```

### Core Layer

**METranscoder** (Main API)
```objective-c
// Create transcoder
METranscoder *transcoder = 
    [[METranscoder alloc] initWithInput:inputURL output:outputURL];

// Configure settings
transcoder.videoEncoderSetting = settings;
transcoder.audioKbps = 192.0;
transcoder.lpcmDepth = 16;

// Set progress callback
transcoder.progressBlock = ^(NSDictionary *info) {
    NSNumber *progress = info[@"progress"];
    NSLog(@"Progress: %.1f%%", [progress floatValue]);
};

// Execute transcode
NSError *error = nil;
BOOL success = [transcoder transcode:&error];

// Cancel operation
[transcoder cancel];
```

**MEManager** (Video Pipeline)
```objective-c
// Usually created internally by METranscoder
MEManager *manager = [[MEManager alloc] initWithInput:input 
                                               output:output];

// Configure encoder
manager.videoEncoderSetting = encoderDict;
manager.filterString = @"scale=1920:1080";

// Monitor status
BOOL failed = manager.failed;
AVAssetWriterStatus status = manager.writerStatus;
```

**MEAudioConverter**
```objective-c
// Usually created internally by METranscoder
MEAudioConverter *converter = 
    [[MEAudioConverter alloc] initWithInput:input 
                                     output:output];

converter.targetKbps = 192.0;
converter.targetDepth = 16;
converter.volumeAdjustment = 0.0; // dB
```

### Pipeline Layer

**MEEncoderPipeline**
```objective-c
// Wrap FFmpeg encoder
// Usually instantiated by MEManager
MEEncoderPipeline *encoder = 
    [[MEEncoderPipeline alloc] initWithConfig:config];

// Encode frame
NSError *error;
BOOL success = [encoder encodeFrame:avFrame error:&error];
```

**MEFilterPipeline**
```objective-c
// Wrap FFmpeg filter graph
MEFilterPipeline *filter = 
    [[MEFilterPipeline alloc] initWithFilterString:@"scale=1280:720"];

// Apply filter
AVFrame *filtered = [filter filterFrame:inputFrame error:&error];
```

**MESampleBufferFactory**
```objective-c
// Create CMSampleBuffer from AVFrame
CMSampleBufferRef sample = 
    [MESampleBufferFactory createSampleBufferFromFrame:avFrame 
                                                timing:timing 
                                                 error:&error];
```

### IO Layer

**MEInput** (AVAssetReader wrapper)
```objective-c
MEInput *input = [[MEInput alloc] initWithURL:url];

// Get track information
AVAssetTrack *videoTrack = input.videoTrack;
AVAssetTrack *audioTrack = input.audioTrack;

// Read samples
CMSampleBufferRef sample = [input copyNextVideoSample];

// Status
AVAssetReaderStatus status = input.status;
```

**MEOutput** (AVAssetWriter wrapper)
```objective-c
MEOutput *output = [[MEOutput alloc] initWithURL:url];

// Add tracks
[output addVideoTrackWithSettings:settings];
[output addAudioTrackWithSettings:settings];

// Write samples
[output appendVideoSample:sample];
[output appendAudioSample:sample];

// Finalize
[output finishWriting];
```

**SBChannel**
```objective-c
// Channel coordination (usually managed internally)
SBChannel *channel = [[SBChannel alloc] initWithInput:input 
                                               output:output];
```

### Utils Layer

**MESecureLogging**
```objective-c
// Safe logging (no format string attacks)
SecureLog(@"Simple message");
SecureLogf(@"Formatted: %d", value);
SecureErrorLog(@"Error occurred");
SecureDebugLog(@"Debug info");

// Multiline output
SecureInfoMultiline(@"Header", @"Footer", @"Line1\nLine2\nLine3");

// Setup FFmpeg logging (call once at startup)
SetupFFmpegLogging();
```

**MEErrorFormatter**
```objective-c
// Convert FFmpeg error codes to NSError
int ret = avcodec_open2(...);
if (ret < 0) {
    NSError *error = 
        [MEErrorFormatter errorWithFFmpegCode:ret
                                     operation:@"encoder open"
                                     component:@"libx264"];
}
```

**MEProgressUtil**
```objective-c
// Calculate progress percentage
CMTime start = kCMTimeZero;
CMTime end = assetDuration;
CMTime current = CMSampleBufferGetPresentationTimeStamp(sample);

double progress = 
    [MEProgressUtil progressPercentForSampleBuffer:sample
                                             start:start
                                               end:end];
// Returns 0.0 to 100.0
```

**MEUtils**
```objective-c
// Video format utilities
CMFormatDescriptionRef formatDesc = 
    [MEUtils createFormatDescriptionForCodec:codecType 
                                        size:size];

// Color space helpers
// PAR calculations
// Various format conversions
```

**parseUtil**
```objective-c
// Parse command-line arguments
NSDictionary *params = parseVideoEncoderOptions(optarg);
NSDictionary *audioParams = parseAudioEncoderOptions(optarg);

// Safe integer parsing
long long value = parseLongLong(string, &valid);
```

**monitorUtil**
```objective-c
// Setup signal handlers
setupSignalHandlers();

// Check for interruption
if (shouldTerminate()) {
    // Cancel operation
}
```

---

## Common Patterns

### Error Handling Pattern

```objective-c
- (BOOL)performOperation:(NSError **)error {
    // Do work
    if (failure) {
        if (error) {
            *error = [NSError errorWithDomain:@"MyDomain"
                                         code:1001
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Operation failed"
            }];
        }
        return NO;
    }
    return YES;
}

// Usage
NSError *error = nil;
if (![self performOperation:&error]) {
    SecureLogf(@"Error: %@", error.localizedDescription);
}
```

### Memory Management Pattern

```objective-c
// Autoreleasepool in hot paths
while (processing) {
    @autoreleasepool {
        // Process sample
        CMSampleBufferRef sample = [input copyNextSample];
        // ... process sample ...
        CFRelease(sample); // Manual release for CF types
    }
}
```

### Progress Reporting Pattern

```objective-c
transcoder.progressBlock = ^(NSDictionary *info) {
    NSNumber *progressNum = info[@"progress"];
    NSNumber *timeRemaining = info[@"timeRemaining"];
    
    printf("\rProgress: %.1f%% (%.0fs remaining)", 
           [progressNum doubleValue], 
           [timeRemaining doubleValue]);
    fflush(stdout);
};
```

### Thread-Safe Property Access

```objective-c
// Atomic property (thread-safe reads)
@property (atomic) BOOL failed;

// For complex objects, use explicit synchronization
- (MEVideoEncoderConfig *)videoEncoderConfig {
    @synchronized(self) {
        return _videoEncoderConfig;
    }
}

- (void)setVideoEncoderConfig:(MEVideoEncoderConfig *)config {
    @synchronized(self) {
        _videoEncoderConfig = config;
    }
}
```

### Core Foundation Bridging

```objective-c
// No ownership transfer (read-only access)
CFTypeRef cfType = (__bridge CFTypeRef)objcObject;

// Transfer ownership to CF (CF must release)
CFTypeRef cfType = (__bridge_retained CFTypeRef)objcObject;

// Transfer ownership from CF (ARC takes over)
NSObject *objcObject = (__bridge_transfer NSObject *)cfType;

// Common pattern for CF types
CMSampleBufferRef sample = [input copyNextSample]; // +1 retain
// ... use sample ...
CFRelease(sample); // Release when done
```

---

## Configuration Keys Reference

### Video Encoder Settings

**Dictionary Keys:**
```objective-c
// Required
kMEVECodecNameKey              // NSString: "libx264" or "libx265"

// Optional
kMEVECodecFrameRateKey         // NSValue(CMTime): e.g. CMTimeMake(30000, 1001)
kMEVECodecBitRateKey           // NSNumber: bitrate in bps, e.g. @(5000000)
kMEVECodecWxHKey               // NSValue(NSSize): e.g. [NSValue valueWithSize:NSMakeSize(1920, 1080)]
kMEVECodecPARKey               // NSValue(NSSize): pixel aspect ratio
kMEVECodecOptionsKey           // NSDictionary: AVOptions for codec
kMEVEx264_paramsKey            // NSString: x264 params, e.g. "keyint=60:bframes=3"
kMEVEx265_paramsKey            // NSString: x265 params
kMEVFFilterStringKey           // NSString: libavfilter string
kMEVECleanApertureKey          // NSValue(NSRect): clean aperture
```

### METranscoder Settings

```objective-c
// Audio settings
kAudioKbpsKey                  // NSNumber(float): target AAC bitrate in kbps
kLPCMDepthKey                  // NSNumber(int): target bit depth (16, 24, 32)
kAudioChannelLayoutTagKey      // NSNumber(uint32_t): target channel layout
kAudioVolumeKey                // NSNumber(float): volume adjustment in dB

// Processing flags
kVideoEncodeKey                // NSNumber(BOOL): enable video encoding
kAudioEncodeKey                // NSNumber(BOOL): enable audio encoding
kCopyFieldKey                  // NSNumber(BOOL): preserve field information
kCopyNCLCKey                   // NSNumber(BOOL): preserve NCLC color info
kCopyOtherMediaKey             // NSNumber(BOOL): copy other media tracks

// Codec selection
kVideoCodecKey                 // NSString: video codec (FourCC as string)
kAudioCodecKey                 // NSString: audio codec (FourCC as string)
```

---

## Testing Guidelines

### Unit Test Structure

```objective-c
@interface MyModuleTests : XCTestCase
@end

@implementation MyModuleTests

- (void)testBasicFunctionality {
    // Arrange
    MEVideoEncoderConfig *config = /* setup */;
    
    // Act
    NSInteger bitrate = config.bitRate;
    
    // Assert
    XCTAssertEqual(bitrate, 5000000);
}

- (void)testErrorCondition {
    // Arrange & Act
    NSError *error = nil;
    MEVideoEncoderConfig *config = 
        [MEVideoEncoderConfig configFromLegacyDictionary:invalidDict 
                                                   error:&error];
    
    // Assert
    XCTAssertNil(config);
    XCTAssertNotNil(error);
}

@end
```

### Integration Test Pattern

```objective-c
- (void)testEndToEndTranscode {
    // Setup
    NSURL *input = [self testInputURL];
    NSURL *output = [self testOutputURL];
    
    METranscoder *transcoder = 
        [[METranscoder alloc] initWithInput:input output:output];
    
    transcoder.videoEncoderSetting = [self testEncoderSettings];
    
    // Execute
    NSError *error = nil;
    BOOL success = [transcoder transcode:&error];
    
    // Verify
    XCTAssertTrue(success, @"Transcode failed: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:output.path]);
    
    // Cleanup
    [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
}
```

---

## Debugging Tips

### Enable Debug Logging

```objective-c
// In your code (before transcoding)
#ifdef DEBUG
    // Enable verbose FFmpeg logging
    av_log_set_level(AV_LOG_VERBOSE);
#endif
```

### Common Issues

**Issue:** "Encoder failed to open"
```
Check:
1. FFmpeg libraries installed correctly
2. Codec name correct ("libx264" not "x264")
3. Encoder settings valid
4. Check MEErrorFormatter message for details
```

**Issue:** "Sample buffer nil"
```
Check:
1. Input file readable
2. Correct track selected
3. Reader status (AVAssetReaderStatusFailed?)
4. Check error from reader
```

**Issue:** "Memory pressure high"
```
Solutions:
1. Add @autoreleasepool in processing loops
2. Release CF types explicitly with CFRelease
3. Check for retain cycles in blocks
4. Monitor with Instruments (Leaks, Allocations)
```

**Issue:** "Deadlock during cancellation"
```
Check:
1. No nested dispatch_sync calls
2. Proper queue ordering
3. Semaphore signal/wait pairing
4. Check MEManager cleanup order
```

---

## Performance Optimization Checklist

- [ ] Use `@autoreleasepool` in sample processing loops
- [ ] Release CF types explicitly (CMSampleBuffer, etc.)
- [ ] Minimize allocations in hot paths
- [ ] Use buffer pooling for repeated allocations
- [ ] Profile with Instruments before optimizing
- [ ] Consider parallel processing for independent operations
- [ ] Use atomic properties for simple state (avoid locks)
- [ ] Batch operations where possible
- [ ] Cache computed values if reused
- [ ] Use efficient data structures (NSArray vs C array)

---

## Security Checklist

- [ ] Use SecureLog/SecureLogf for all logging
- [ ] Validate all user input
- [ ] Check array bounds before access
- [ ] Validate file paths (no traversal)
- [ ] Handle integer overflow in calculations
- [ ] Sanitize strings before logging
- [ ] Use NSError for error propagation (not exceptions)
- [ ] Release resources on all error paths
- [ ] Check NULL/nil before dereferencing
- [ ] Use size_t for buffer sizes

---

## Code Style Guidelines

### Naming Conventions

```objective-c
// Classes: ME prefix + CamelCase
@interface METranscoder : NSObject

// Methods: camelCase starting lowercase
- (BOOL)transcode:(NSError **)error;

// Properties: camelCase starting lowercase
@property (nonatomic) NSInteger bitRate;

// Constants: k + ME + CamelCase
extern NSString* const kMEVECodecNameKey;

// Enums: ME + CamelCase
typedef NS_ENUM(NSUInteger, MEVideoCodecKind) {
    MEVideoCodecKindX264
};
```

### Header Structure

```objective-c
//
//  MEModuleName.h
//  movencoder2
//
//  Created by [Author] on [Date].
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

/*
 * This file is part of movencoder2.
 * [GPL v2 license text]
 */

#ifndef MEModuleName_h
#define MEModuleName_h

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

// Interface declarations

NS_ASSUME_NONNULL_END

#endif /* MEModuleName_h */
```

### Implementation Structure

```objective-c
#import "MEModuleName.h"
#import "MEDependency.h"

// Constants
NSString* const kMEConstantKey = @"value";

// Private interface
@interface MEModuleName ()
@property (nonatomic) InternalType *privateProperty;
@end

@implementation MEModuleName

// Initialization
- (instancetype)init {
    self = [super init];
    if (self) {
        // Setup
    }
    return self;
}

// Public methods

// Private methods (prefixed with underscore optional)

// Dealloc (if needed for cleanup)
- (void)dealloc {
    // Cleanup
}

@end
```

---

## Useful Commands

### Build Commands

```bash
# Clean build
$ xcodebuild clean -scheme movencoder2

# Build for release
$ xcodebuild -scheme movencoder2 -configuration Release

# Build and archive
$ xcodebuild archive -scheme movencoder2 \
    -archivePath build/movencoder2.xcarchive
```

### Test Commands

```bash
# Run all tests
$ xcodebuild test -scheme movencoder2

# Run specific test
$ xcodebuild test -scheme movencoder2 \
    -only-testing:movencoder2Tests/MEVideoEncoderConfigTests

# Generate coverage report
$ xcodebuild test -scheme movencoder2 -enableCodeCoverage YES
```

### Analysis Commands

```bash
# Static analysis
$ xcodebuild analyze -scheme movencoder2

# Count lines of code
$ find movencoder2 -name "*.m" -o -name "*.h" | xargs wc -l

# Find TODOs
$ grep -r "TODO\|FIXME" movencoder2 --include="*.m" --include="*.h"
```

---

## Resources

### Documentation
- [README.md](../README.md) - Project overview and features
- [HowToBuildLibs.md](../HowToBuildLibs.md) - External library build guide
- [PROJECT_REVIEW.md](PROJECT_REVIEW.md) - Comprehensive project review
- [ARCHITECTURE.md](ARCHITECTURE.md) - Architecture overview

### External References
- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [AVFoundation Programming Guide](https://developer.apple.com/av-foundation/)
- [Core Media Reference](https://developer.apple.com/documentation/coremedia)
- [x264 Options](https://www.videolan.org/developers/x264.html)
- [x265 Options](https://x265.readthedocs.io/)

---

**Document Version:** 1.0  
**Maintainer:** MyCometG3  
**Last Review:** December 2025
