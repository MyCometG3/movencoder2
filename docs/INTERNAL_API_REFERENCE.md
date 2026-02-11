# Internal API Reference

**Last Updated:** February 2026  
**Audience:** Library maintainers and contributors

---

## Overview

This document describes the internal APIs of movencoder2. These APIs are **not part of the public interface** and may change without notice between versions. They are intended for use within the library implementation only.

⚠️ **Warning:** If you are using movencoder2 as a library/framework, you should **only** use the public APIs documented in [API_GUIDELINES.md](API_GUIDELINES.md). Internal APIs are subject to change.

---

## Internal Architecture Layers

### Layer 1: Core Components (Internal)

#### MEManager
**Location:** `Core/MEManager.h`

**Purpose:** Video encoding pipeline orchestration

**Key Responsibilities:**
- Manages video encoder pipeline (MEEncoderPipeline)
- Manages video filter pipeline (MEFilterPipeline)
- Coordinates sample buffer processing
- Handles encoder configuration
- Manages encoding state and status

**Key Constants:**
- `kMEVECodecNameKey` - Codec name (e.g., "libx264")
- `kMEVECodecOptionsKey` - Codec options dictionary
- `kMEVEx264_paramsKey` - x264 parameter string
- `kMEVEx265_paramsKey` - x265 parameter string
- `kMEVECodecFrameRateKey` - Frame rate
- `kMEVECodecWxHKey` - Video dimensions
- `kMEVECodecPARKey` - Pixel aspect ratio
- `kMEVFFilterStringKey` - Filter graph string
- `kMEVECodecBitRateKey` - Bitrate
- `kMEVECleanApertureKey` - Clean aperture

**Key Methods:**
```objective-c
- (instancetype)initWith:(AVAssetReaderTrackOutput*)readerOutput
                      to:(AVAssetWriterInput*)writerInput
                    size:(NSSize)size;
- (void)setupMEEncoderWith:(NSDictionary*)setting
                      size:(NSSize)size;
- (void)setupMEFilterWith:(NSString*)filterString
                     size:(NSSize)size;
```

**Internal Bridge Aliases (IO Adapters):**
```objective-c
- (BOOL)appendSampleBufferInternal:(CMSampleBufferRef)sb;
- (BOOL)isReadyForMoreMediaDataInternal;
- (void)markAsFinishedInternal;
- (void)requestMediaDataWhenReadyOnQueueInternal:(dispatch_queue_t)queue
                                     usingBlock:(RequestHandler)block;
```

#### MEAudioConverter
**Location:** `Core/MEAudioConverter.h`

**Purpose:** Audio processing and conversion

**Key Responsibilities:**
- Audio format conversion
- Channel layout transformation
- Bitrate control
- Sample rate conversion
- Audio buffer management

**Key Methods:**
```objective-c
- (instancetype)initWith:(AVAssetReaderTrackOutput*)readerOutput
                      to:(AVAssetWriterInput*)writerInput;
```

**Internal Bridge Aliases (IO Adapters):**
```objective-c
- (BOOL)appendSampleBufferInternal:(CMSampleBufferRef)sb;
- (BOOL)isReadyForMoreMediaDataInternal;
- (void)markAsFinishedInternal;
- (void)requestMediaDataWhenReadyOnQueueInternal:(dispatch_queue_t)queue
                                     usingBlock:(RequestHandler)block;
- (CMTimeScale)mediaTimeScaleInternal;
- (void)setMediaTimeScaleInternal:(CMTimeScale)mediaTimeScale;
- (nullable CMSampleBufferRef)copyNextSampleBufferInternal CF_RETURNS_RETAINED;
```

**Test Helper Methods (Internal):**
```objective-c
- (nullable AVAudioPCMBuffer*)createPCMBufferFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
                                                    withFormat:(AVAudioFormat*)format;
- (nullable CMSampleBufferRef)createSampleBufferFromPCMBuffer:(AVAudioPCMBuffer*)pcmBuffer
                                  withPresentationTimeStamp:(CMTime)pts
                                                     format:(AVAudioFormat*)format CF_RETURNS_RETAINED;
```

#### METranscoder Internal Extensions
**Location:** `Core/METranscoder+Internal.h`

**Purpose:** Private METranscoder implementation details

**Categories:**
- `METranscoder()` - Private properties and ivars
- `METranscoder(paramParser)` - Parameter parsing
- `METranscoder(prepareChannels)` - Channel setup

**Private Properties:**
```objective-c
@property (strong, nonatomic, nullable) AVAssetReader* assetReader;
@property (strong, nonatomic, nullable) AVAssetWriter* assetWriter;
@property (strong, nonatomic, nullable) dispatch_queue_t controlQueue;
@property (strong, nonatomic, nullable) dispatch_queue_t processQueue;
@property (strong, nonatomic) NSMutableArray<SBChannel*>* sbChannels;
@property (strong, nonatomic, nullable) NSMutableDictionary* managers;
```

#### METranscodeConfiguration
**Location:** `Core/METranscodeConfiguration.h`

**Purpose:** Consolidated internal configuration for METranscoder

**Key Responsibilities:**
- Holds legacy-compatible `encodingParams`
- Stores time range and logging/callbacks
- Bridges CLI/paramParser settings to internal usage

---

### Layer 2: Pipeline Components (Internal)

#### MEEncoderPipeline
**Location:** `Pipeline/MEEncoderPipeline.h`

**Purpose:** Video encoder abstraction

**Supported Encoders:**
- libavcodec (libx264, libx265)
- AVFoundation VideoToolbox encoders

**Key Methods:**
```objective-c
- (instancetype)initWithConfig:(MEVideoEncoderConfig*)config
                          size:(CGSize)size;
- (CVPixelBufferRef)encode:(CVPixelBufferRef)srcBuffer
                     error:(NSError**)error;
```

#### MEFilterPipeline
**Location:** `Pipeline/MEFilterPipeline.h`

**Purpose:** libavfilter integration for video filtering

**Capabilities:**
- FFmpeg filter graph management
- Frame format conversion
- Complex video filtering operations

**Key Methods:**
```objective-c
- (instancetype)initWithFilterString:(NSString*)filterString
                         sourceSize:(CGSize)size;
- (CVPixelBufferRef)filter:(CVPixelBufferRef)srcBuffer
                     error:(NSError**)error;
```

#### MESampleBufferFactory
**Location:** `Pipeline/MESampleBufferFactory.h`

**Purpose:** Create and manage CMSampleBuffer objects

**Key Responsibilities:**
- Pixel buffer to sample buffer conversion
- Timing information management
- Format description creation

**Key Methods:**
```objective-c
+ (CMSampleBufferRef)createSampleBufferFrom:(CVPixelBufferRef)pixelBuffer
                                 formatDesc:(CMFormatDescriptionRef)formatDesc
                                 timingInfo:(CMSampleTimingInfo)timing;
```

---

### Layer 3: IO Components (Internal)

#### MEInput
**Location:** `IO/MEInput.h`

**Purpose:** AVAssetReader abstraction

**Key Responsibilities:**
- Asset reading lifecycle management
- Track output coordination
- Sample buffer delivery
- Reading status monitoring

**Key Methods:**
```objective-c
- (instancetype)initWithAsset:(AVAsset*)asset;
- (BOOL)startReading:(NSError**)error;
- (CMSampleBufferRef)copyNextSampleBuffer;
```

#### MEOutput
**Location:** `IO/MEOutput.h`

**Purpose:** AVAssetWriter abstraction

**Key Responsibilities:**
- Asset writing lifecycle management
- Writer input coordination
- Sample buffer acceptance
- Writing status monitoring

**Key Methods:**
```objective-c
- (instancetype)initWithURL:(NSURL*)outputURL;
- (BOOL)startWriting:(NSError**)error;
- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer;
```

#### SBChannel
**Location:** `IO/SBChannel.h`

**Purpose:** Sample buffer channel coordination

**Key Responsibilities:**
- Reader/writer binding
- Channel state management
- Asynchronous I/O coordination
- Error propagation

**Key Methods:**
```objective-c
- (instancetype)initWithReader:(MEInput*)reader
                        writer:(MEOutput*)writer;
- (void)startProcessing;
```

---

### Layer 4: Utility Components (Internal)

#### MECommon
**Location:** `Utils/MECommon.h`

**Purpose:** Common constants and macros

**Key Definitions:**
- `ALog()` macro for debug logging
- Audio channel layout constants
- Progress callback keys (re-exported in public API)

**Constants:**
```objective-c
extern const AudioChannelLayoutTag kMEMPEGSourceLayouts[8];
extern const AudioChannelLayoutTag kMEAACDestinationLayouts[8];
```

#### MEUtils
**Location:** `Utils/MEUtils.h`

**Purpose:** Video format and FFmpeg utilities
**Implementation:** Split into `MEPixelFormatUtils` and `MEMetadataExtractor`.

**Key Capabilities:**
- Format descriptor manipulation
- Color space conversion
- Pixel format mapping (AVFoundation ↔ FFmpeg)
- Video property extraction

**Key Functions:**
```objective-c
CMFormatDescriptionRef createFormatDescription(/* parameters */);
NSString* describeVideoFormat(CMFormatDescriptionRef format);
enum AVPixelFormat pixelFormatFromCVPixelFormat(OSType cvFormat);
```

#### MEPixelFormatUtils
**Location:** `Utils/MEPixelFormatUtils.h`

**Purpose:** Pixel format mapping helpers

#### MEMetadataExtractor
**Location:** `Utils/MEMetadataExtractor.h`

**Purpose:** CMSampleBuffer/AVFrame metadata extraction

#### MESecureLogging
**Location:** `Utils/MESecureLogging.h`

**Purpose:** Secure logging infrastructure

**Key Features:**
- Format string attack prevention
- FFmpeg log redirection
- Multi-level logging (info, error, debug)

**Key Functions:**
```objective-c
void SecureLog(NSString* message);
void SecureLogf(NSString* format, ...) NS_FORMAT_FUNCTION(1,2);
void SetupFFmpegLogging(void);
```

#### MEProgressUtil
**Location:** `Utils/MEProgressUtil.h`

**Purpose:** Progress calculation utilities

**Key Methods:**
```objective-c
+ (float)progressPercentForSampleBuffer:(CMSampleBufferRef)buffer
                                  start:(CMTime)start
                                    end:(CMTime)end;
```

#### MEErrorFormatter
**Location:** `Utils/MEErrorFormatter.h`

**Purpose:** Error message formatting

**Key Methods:**
```objective-c
+ (NSString*)stringFromNSError:(NSError*)error;
+ (NSString*)stringFromFFmpegCode:(int)errcode;
```

#### parseUtil
**Location:** `Utils/parseUtil.h`

**Purpose:** Command-line parameter parsing

**Key Functions:**
```objective-c
NSNumber* parseInteger(NSString* val);
NSValue* parseTime(NSString* val);
NSDictionary* parseCodecOptions(NSString* val);
```

#### monitorUtil
**Location:** `Utils/monitorUtil.h`

**Purpose:** Signal handling and process monitoring

**Key Functions:**
```objective-c
void startMonitor(monitor_block_t mon, cancel_block_t can);
void finishMonitor(int code, NSString* msg, NSString* errMsg);
int lastSignal(void);
```

---

## Internal Data Flow

### Transcoding Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                      METranscoder                            │
│                   (Public Interface)                         │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴────────────┐
         │                        │
         ▼                        ▼
┌─────────────────┐      ┌─────────────────┐
│   MEManager     │      │ MEAudioConverter │
│ (Video Pipeline)│      │ (Audio Pipeline) │
└────┬────────────┘      └─────────────────┘
     │
     ├──► MEFilterPipeline ──► MEEncoderPipeline
     │         (libavfilter)      (libavcodec)
     │
     ▼
┌──────────────────────────────────────┐
│           SBChannel                   │
│  (Coordinates Reader/Writer)          │
└──────┬──────────────────────┬────────┘
       │                      │
       ▼                      ▼
┌─────────────┐      ┌─────────────┐
│  MEInput    │      │  MEOutput   │
│ (AVAssetRdr)│      │ (AVAssetWrt)│
└─────────────┘      └─────────────┘
```

### Sample Buffer Processing

```
1. MEInput copies next sample buffer from AVAssetReader
2. SBChannel delivers sample buffer to appropriate processor
3. For video:
   a. MEFilterPipeline applies filters (if configured)
   b. MEEncoderPipeline encodes the frame
   c. MESampleBufferFactory creates output sample buffer
4. For audio:
   a. MEAudioConverter performs format conversion
5. MEOutput appends sample buffer to AVAssetWriter
6. Progress callbacks fired via MEProgressUtil calculations
```

---

## Threading Model

### Queue Structure

- **Control Queue** (`controlQueue`)
  - Serial queue for transcoder state management
  - Handles start/stop/cancel operations
  - Manages lifecycle events

- **Process Queue** (`processQueue`)
  - Concurrent queue for sample processing
  - Multiple channels process in parallel
  - Synchronized via SBChannel coordination

### Thread Safety

- **METranscoder**: Thread-safe public interface via atomic properties
- **MEManager**: Thread-confined to process queue
- **SBChannel**: Thread-safe coordination with reader/writer queues
- **Utilities**: Generally thread-safe (except where noted)

---

## Extension Points

### Adding New Encoders

To add a new encoder to MEEncoderPipeline:

1. Add encoder kind to `MEVideoCodecKind` enum
2. Implement encoder initialization in `MEEncoderPipeline.m`
3. Add encoder-specific configuration to `MEVideoEncoderConfig`
4. Update codec name parsing in `METypes.h`

### Adding New Filters

To add filter support:

1. Update `MEFilterPipeline` to handle new filter types
2. Add filter string parsing to parameter parser
3. Document filter syntax in README

### Adding New Input/Output Formats

Currently limited to AVFoundation-supported formats. To extend:

1. Create custom reader/writer implementations
2. Abstract MEInput/MEOutput to protocol
3. Add format detection in METranscoder

---

## Testing Internal APIs

### Unit Testing

Internal components should have comprehensive unit tests:

```objective-c
// Example test for MEVideoEncoderConfig
- (void)testVideoEncoderConfig {
    NSDictionary *dict = @{@"c": @"libx264", @"r": @"30000:1001"};
    NSError *error = nil;
    MEVideoEncoderConfig *config = [MEVideoEncoderConfig configFromLegacyDictionary:dict error:&error];

    XCTAssertNotNil(config);
    XCTAssertEqual(config.codecKind, MEVideoCodecKindX264);
    XCTAssertTrue(config.hasFrameRate);
}
```

### Integration Testing

Test complete pipeline with real media:

```objective-c
- (void)testTranscodePipeline {
    METranscoder *transcoder = [[METranscoder alloc] initWithInput:testInput output:testOutput];
    [transcoder startAsync];

    // Wait for completion
    // Verify output file
}
```

---

## Performance Considerations

### Critical Paths

1. **Sample buffer processing** (hottest path)
   - Minimize allocations in encode/filter loops
   - Reuse pixel buffers where possible
   - Avoid unnecessary format conversions

2. **Memory management**
   - Release sample buffers promptly
   - Use autorelease pools in tight loops
   - Monitor memory pressure

3. **Queue dispatching**
   - Batch operations when possible
   - Minimize cross-queue synchronization
   - Use async dispatch for I/O

### Profiling Points

- Encoder throughput (frames per second)
- Memory allocation patterns
- Queue contention
- FFmpeg filter performance

---

## Debugging Tips

### Enable Verbose Logging

```objective-c
transcoder.verbose = YES;
```

### FFmpeg Log Redirection

```objective-c
SetupFFmpegLogging(); // Redirects FFmpeg logs to SecureLogging
```

### Breakpoint Locations

- `MEManager -encodeFrame:error:` - Video encoding
- `MEAudioConverter -convertSampleBuffer:` - Audio conversion
- `SBChannel -processNextBuffer` - Buffer coordination
- `METranscoder -handleError:` - Error handling

### Instruments Profiles

- Time Profiler: Identify hot spots
- Allocations: Track memory usage
- Leaks: Find memory leaks
- System Trace: Thread coordination

---

## Contributing Guidelines

When modifying internal APIs:

1. **Maintain thread safety** - Document any thread requirements
2. **Add unit tests** - Cover new functionality
3. **Update documentation** - Keep this reference current
4. **Performance test** - Verify no regressions
5. **Review public API impact** - Ensure no leakage to public interface

---

## Future Refactoring Considerations

### Potential Improvements

1. **Protocol-based architecture**
   - Define protocols for encoders, filters, readers, writers
   - Enable easier extension and testing

2. **Dependency injection**
   - Reduce coupling between components
   - Improve testability

3. **Error handling**
   - More granular error types
   - Better error recovery strategies

4. **Configuration**
   - Fully migrate away from dictionary-based config
   - Type-safe configuration throughout

---

## Related Documentation

- [API_GUIDELINES.md](API_GUIDELINES.md) - Public API documentation
- [ARCHITECTURE.md](ARCHITECTURE.md) - High-level architecture
- [PROJECT_REVIEW.md](PROJECT_REVIEW.md) - Project overview

---

**Note:** This is internal documentation for library maintainers. For public API usage, refer to [API_GUIDELINES.md](API_GUIDELINES.md).
