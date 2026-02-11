# Architecture Overview

**Document Version:** 1.0  
**Last Updated:** February 2026

---

## Introduction

This document provides a comprehensive overview of the movencoder2 architecture, including module responsibilities, data flow, and key design decisions.

---

## System Architecture

### High-Level Overview

movencoder2 implements a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────┐
│                    CLI Layer (main.m)                    │
│              Command-line parsing & orchestration        │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│              Control Layer (Core/METranscoder)           │
│         High-level transcoding coordination              │
└─────────────────────┬───────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────┐
│          Processing Layer (Core/MEManager)               │
│      Video/Audio encoding pipeline orchestration         │
└────┬─────────────────────────────────────────────┬──────┘
     │                                              │
┌────▼──────────────────────┐       ┌──────────────▼──────┐
│   Pipeline Components     │       │   Audio Processing  │
│  (Pipeline/*)             │       │ (Core/MEAudioConv)  │
└────┬──────────────────────┘       └──────────────────────┘
     │
┌────▼──────────────────────────────────────────────────────┐
│              I/O Layer (IO/MEInput, MEOutput)             │
│        AVAssetReader/Writer abstraction & channels        │
└───────────────────────────┬───────────────────────────────┘
                            │
┌───────────────────────────▼───────────────────────────────┐
│         Infrastructure (Utils/*, Config/*)                │
│    Logging, Error Formatting, Progress, Configuration     │
└───────────────────────────────────────────────────────────┘
```

---

## Module Breakdown

### 1. Config Layer

**Purpose:** Type-safe configuration and type definitions

**Components:**
- `METypes.h` - Enum definitions (MEVideoCodecKind)
- `MEVideoEncoderConfig.h/m` - Type-safe encoder configuration adapter

**Responsibilities:**
- Define codec type enumerations
- Provide type-safe configuration interface
- Validate configuration parameters
- Parse and normalize settings (bitrate strings, codec params)
- Collect validation issues for user feedback

**Key Design Decisions:**
- Acts as an adapter over legacy dictionary-based configuration
- Immutable configuration objects for thread safety
- Validation issue collection instead of throwing errors

---

### 2. Core Layer

**Purpose:** Central transcoding orchestration and core business logic

#### METranscoder

**Role:** High-level transcoding controller (Facade pattern)

**Responsibilities:**
- Public API for transcoding operations
- Input/output file management
- Progress callback coordination
- Error handling and recovery
- Configuration management
- Temporary file cleanup

**Internal Configuration:**
- `METranscodeConfiguration` consolidates encoding params, time range, logging, and callbacks.

**Key Methods:**
```objective-c
- (instancetype)initWithInput:(NSURL*)input output:(NSURL*)output;
- (BOOL)transcode:(NSError**)error;
- (void)cancel;
```

**Categories:**
- `METranscoder+paramParser.m` - Parameter parsing logic
- `METranscoder+prepareChannels.m` - Channel preparation logic
- `METranscoder+Internal.h` - Private interface

#### MEManager

**Role:** Video encoding pipeline manager and coordinator

**Responsibilities:**
- FFmpeg encoder/filter initialization and management
- Video frame processing and encoding
- Filter graph setup and management
- Encoder pipeline coordination
- Sample buffer transformation
- Progress reporting

**Internal Bridge APIs:**
- IO adapters call `*Internal` aliases (appendSampleBufferInternal, isReadyForMoreMediaDataInternal, markAsFinishedInternal).

**Key Properties:**
```objective-c
@property (readonly) BOOL failed;
@property (readonly) AVAssetWriterStatus writerStatus;
@property (readonly) AVAssetReaderStatus readerStatus;
```

**Concurrency Model:**
- Serial dispatch queue for encoder operations
- Atomic properties for status flags
- Thread-safe state management

#### MEAudioConverter

**Role:** Audio processing coordinator

**Responsibilities:**
- Audio format conversion
- Channel layout transformation
- Bit depth conversion
- AAC encoding
- Audio sample processing
- Buffer pool management

**Internal Bridge APIs:**
- IO adapters call `*Internal` aliases for sample buffer flow and readiness.

**Optimization Techniques:**
- Buffer pooling for memory efficiency
- Autoreleasepool optimization in hot paths
- Efficient format conversion

---

### 3. Pipeline Layer

**Purpose:** Modular encoding and filtering components

#### MEEncoderPipeline

**Role:** Video encoder abstraction

**Responsibilities:**
- FFmpeg encoder initialization
- Encoder configuration
- Frame encoding
- Encoder cleanup

**Supported Encoders:**
- libx264 (H.264)
- libx265 (H.265)

#### MEFilterPipeline

**Role:** Video filter graph management

**Responsibilities:**
- FFmpeg filter graph setup
- Filter configuration
- Frame filtering
- Filter graph cleanup

**Filter Operations:**
- Format conversion
- Video processing
- Custom filter chains

#### MESampleBufferFactory

**Role:** Sample buffer creation (Factory pattern)

**Responsibilities:**
- CMSampleBuffer creation from AVFrame
- Format descriptor management
- Timing information handling
- Memory-efficient buffer allocation

---

### 4. IO Layer

**Purpose:** Asset reading/writing abstraction

#### MEInput

**Role:** Asset reader wrapper

**Responsibilities:**
- AVAssetReader management
- Track selection and configuration
- Sample buffer reading
- Reader status monitoring

**Bridge Interaction:**
- Delivers sample buffers through SBChannel to Core via internal bridge aliases.

**Features:**
- Support for multiple tracks (video, audio, other)
- Automatic format handling
- Progress tracking

#### MEOutput

**Role:** Asset writer wrapper

**Responsibilities:**
- AVAssetWriter management
- Track configuration
- Sample buffer writing
- Writer status monitoring

**Bridge Interaction:**
- Accepts processed buffers from Core via internal bridge aliases.

**Features:**
- Multiple track writing
- Metadata preservation
- File format handling

#### SBChannel

**Role:** Sample buffer channel coordination

**Responsibilities:**
- Reader-to-writer channel mapping
- Sample buffer flow control
- Channel lifecycle management
- Progress monitoring

**Bridge Interaction:**
- Interacts directly with MEManager/MEAudioConverter (including audio paths that bypass MEInput/MEOutput wrappers); `Internal` aliases are available for migration.

**Optimization:**
- Autoreleasepool for memory pressure reduction
- Efficient buffer handling

---

### 5. Utils Layer

**Purpose:** Cross-cutting utilities and helpers

#### MECommon

**Constants and shared definitions:**
- String constants for keys
- Common enumerations
- Shared type definitions

#### MEUtils

**Video format utilities:**
- Format descriptor helpers
- Color space conversions
- Aspect ratio calculations
- Video property utilities

**LOC:** wrapper (implementation split into MEPixelFormatUtils/MEMetadataExtractor)

#### MEPixelFormatUtils

**Pixel format utilities:**
- AVFoundation ↔ FFmpeg format mapping
- Pixel format discovery helpers

#### MEMetadataExtractor

**Sample buffer metadata utilities:**
- CMSampleBuffer/AVFrame metadata extraction
- Attachment dictionary creation

#### MESecureLogging

**Secure logging infrastructure:**
- Format string attack prevention
- FFmpeg log redirection
- Log sanitization
- Multi-level logging (info, error, debug)

**Functions:**
```objective-c
void SecureLog(NSString* message);
void SecureLogf(NSString* format, ...) NS_FORMAT_FUNCTION(1,2);
NSString* sanitizeLogString(NSString* input);
void SetupFFmpegLogging(void);
```

**Security Features:**
- All format strings validated
- Injection attack prevention
- Controlled FFmpeg output

#### MEErrorFormatter

**Human-friendly error messages:**
- FFmpeg error code translation
- Contextual error information
- User-friendly descriptions

**Usage:**
```objective-c
NSError *error = [MEErrorFormatter errorWithFFmpegCode:ret
                                              operation:@"encoder open"
                                              component:@"libx264"];
```

#### MEProgressUtil

**Progress calculation:**
- Sample buffer progress tracking
- Percentage calculation
- Time-based progress reporting

**Extracted from inline logic for reusability**

#### parseUtil

**Command-line parsing:**
- Safe parameter parsing
- Integer overflow protection
- String sanitization
- Argument validation

**LOC:** 359

#### monitorUtil

**Process monitoring:**
- Signal handling
- Interrupt detection
- Graceful shutdown

**LOC:** 169

---

## Data Flow

### Transcoding Workflow

```
1. CLI Entry (main.m)
   │
   ├─▶ Parse command-line arguments (parseUtil)
   │
   ├─▶ Create METranscoder instance
   │
   └─▶ Call transcode method

2. METranscoder (Control Layer)
   │
   ├─▶ Validate input/output URLs
   │
   ├─▶ Parse video encoder settings → MEVideoEncoderConfig
   │
   ├─▶ Create MEInput (reader) and MEOutput (writer)
   │
   ├─▶ Create MEManager for video encoding
   │
   ├─▶ Create MEAudioConverter for audio processing
   │
   └─▶ Prepare and start channels

3. MEManager (Processing Layer)
   │
   ├─▶ Initialize FFmpeg encoder (MEEncoderPipeline)
   │
   ├─▶ Initialize FFmpeg filter (MEFilterPipeline)
   │
   ├─▶ Create sample buffer factory (MESampleBufferFactory)
   │
   └─▶ Start encoding loop

4. Encoding Loop (MEManager)
   │
   ├─▶ Read video frame from MEInput
   │
   ├─▶ Apply filters (MEFilterPipeline)
   │
   ├─▶ Encode frame (MEEncoderPipeline)
   │
   ├─▶ Convert to CMSampleBuffer (MESampleBufferFactory)
   │
   ├─▶ Write to MEOutput
   │
   ├─▶ Report progress (MEProgressUtil)
   │
   └─▶ Repeat until done

5. Audio Processing (MEAudioConverter)
   │
   ├─▶ Read audio samples from MEInput
   │
   ├─▶ Convert format/layout as needed
   │
   ├─▶ Encode to AAC
   │
   ├─▶ Write to MEOutput
   │
   └─▶ Parallel with video processing

6. Completion
   │
   ├─▶ Finalize MEOutput (finish writing)
   │
   ├─▶ Cleanup resources
   │
   ├─▶ Cleanup temporary files (METranscoder)
   │
   └─▶ Return success/error
```

---

## Threading Model

### Queue Architecture

**Main Thread:**
- CLI initialization
- User interaction
- Final result handling

**MEManager Queue (Serial):**
- Video encoder operations
- FFmpeg calls
- Frame processing
- State management

**MEAudioConverter Queue (Serial):**
- Audio conversion operations
- Format transformations
- AAC encoding

**Reader/Writer Queues:**
- AVAssetReader operations
- AVAssetWriter operations
- Sample buffer I/O

### Synchronization

**Atomic Properties:**
```objective-c
@property (atomic) BOOL failed;
@property (atomic) AVAssetWriterStatus writerStatus;
@property (atomic) AVAssetReaderStatus readerStatus;
```

**Semaphores:**
- Completion signaling
- Multi-queue coordination
- Progress synchronization

**Serial Queues:**
- Prevent race conditions
- Ensure operation ordering
- State consistency

**Best Practices:**
- No nested dispatch_sync (deadlock prevention)
- Clear queue ownership
- Proper cleanup ordering

---

## Design Patterns

### 1. Facade Pattern
**Implementation:** METranscoder
- Simplifies complex subsystem (MEManager, MEAudioConverter, IO)
- Provides unified interface
- Hides internal complexity

### 2. Adapter Pattern
**Implementation:** MEVideoEncoderConfig
- Adapts legacy dictionary-based config to type-safe interface
- Maintains backward compatibility
- Adds validation layer

### 3. Factory Pattern
**Implementation:** MESampleBufferFactory
- Encapsulates CMSampleBuffer creation
- Manages format descriptors
- Handles memory allocation

### 4. Strategy Pattern
**Implementation:** MEEncoderPipeline / MEFilterPipeline
- Interchangeable encoding strategies (x264/x265)
- Pluggable filter implementations
- Runtime configuration

### 5. Observer Pattern
**Implementation:** Progress callbacks
- Block-based progress reporting
- Asynchronous notification
- Decoupled progress handling

---

## Memory Management Strategy

### ARC Guidelines

**Primary Strategy:** Automatic Reference Counting (ARC)
- Used for all Objective-C objects
- Proper strong/weak reference management
- Careful attention to retain cycles

### Core Foundation Bridging

**Bridging Patterns:**
```objective-c
// Ownership transfer
CFTypeRef cfRef = (__bridge_retained CFTypeRef)objcObject;

// No ownership transfer
CFTypeRef cfRef = (__bridge CFTypeRef)objcObject;

// Ownership acceptance
NSObject *objcObject = (__bridge_transfer NSObject *)cfRef;
```

**Count:** 53 bridging instances throughout codebase

### Manual Memory Management

**Autoreleasepool Optimization:**
- 16 strategic placements
- Hot path memory pressure reduction
- Loop-based autoreleasepool

**Example:**
```objective-c
while (processing) {
    @autoreleasepool {
        // Intensive processing
        // Temporary objects released each iteration
    }
}
```

### Buffer Management

**Audio Buffer Pooling:**
- Reusable buffer allocation
- Reduces allocation overhead
- Pool-based memory management

**Video Buffer Handling:**
- Zero-copy where possible
- Efficient Core Foundation patterns
- Minimal temporary allocations

---

## Error Handling Strategy

### Error Propagation

**NSError Pattern:**
```objective-c
- (BOOL)operation:(NSError **)error {
    if (failure) {
        if (error) {
            *error = [self createError:...];
        }
        return NO;
    }
    return YES;
}
```

### Error Formatting

**MEErrorFormatter:**
- Translates FFmpeg error codes
- Provides contextual information
- User-friendly descriptions

**Example:**
```objective-c
// FFmpeg returns -22 (EINVAL)
// Formatted as: "Failed to open encoder libx264: Invalid argument"
```

### Resource Cleanup

**Error Path Handling:**
- Proper cleanup on all error paths
- No resource leaks on failure
- State rollback when needed

---

## Configuration Management

### Legacy Dictionary-Based Config

**Original Approach:**
```objective-c
NSDictionary *settings = @{
    kMEVECodecNameKey: @"libx264",
    kMEVECodecBitRateKey: @(5000000),
    // ... more keys
};
```

**Issues:**
- No compile-time type safety
- Error-prone key usage
- Validation at runtime only

### Type-Safe Config (New)

**Modern Approach:**
```objective-c
MEVideoEncoderConfig *config = 
    [MEVideoEncoderConfig configFromLegacyDictionary:settings 
                                               error:&error];

// Type-safe access
MEVideoCodecKind codec = config.codecKind;
NSInteger bitrate = config.bitRate;
CMTime frameRate = config.frameRate;
```

**Benefits:**
- Compile-time type checking
- Validation with issue collection
- Immutable configuration
- Clear API surface

---

## Security Architecture

### Secure Logging

**Threat Model:**
- Format string injection attacks
- Log injection attacks
- Sensitive data exposure

**Mitigation:**
```objective-c
// Vulnerable: NSLog(@"%@", userInput); // If userInput contains %@
// Safe: SecureLog(userInput);

// Vulnerable: NSLog(formatString, ...);
// Safe: SecureLogf(formatString, ...); // Internal sanitization
```

**FFmpeg Integration:**
```objective-c
void SetupFFmpegLogging(void);
// Redirects all FFmpeg log output through secure logging
```

### Input Validation

**File Path Validation:**
- Path traversal prevention
- Boundary enforcement
- URL validation

**Parameter Validation:**
- Integer overflow checks
- String length limits
- Format validation

### Memory Safety

**Buffer Operations:**
- Size validation before allocation
- Bounds checking on access
- Safe string operations

---

## Performance Optimizations

### Memory Optimizations

1. **Buffer Pooling** (MEAudioConverter)
   - Reusable buffer allocation
   - Reduced GC pressure

2. **Autoreleasepool** (16 instances)
   - Hot path memory pressure reduction
   - Loop-based temporary object cleanup

3. **Zero-Copy Patterns**
   - Core Foundation bridging without copy
   - Direct buffer access where safe

### Concurrency Optimizations

1. **Parallel Processing**
   - Concurrent video/audio encoding
   - Multiple dispatch queues
   - Independent pipeline operations

2. **Efficient Synchronization**
   - Atomic properties for lock-free reads
   - Semaphores for coordination
   - Minimal critical sections

### Algorithmic Optimizations

1. **Efficient Sample Processing**
   - Minimal allocations in loops
   - Direct API usage without wrappers
   - Strategic caching

2. **Progress Calculation**
   - Extracted to utility (MEProgressUtil)
   - Efficient time-based computation
   - Minimal overhead

---

## Future Architecture Considerations

### Public API Formalization

**Current State:** Internal architecture exposed

**Proposed Changes:**
- Define clear public API surface
- Create umbrella header (MovEncoder2.h)
- Separate public/internal interfaces
- Document public API contracts

**Benefits:**
- Framework distribution ready
- Clear API stability guarantees
- Reduced coupling to internals

### Package Manager Support

**Potential Additions:**
- Swift Package Manager integration
- CocoaPods specification
- Carthage compatibility

**Requirements:**
- Public API formalization
- Semantic versioning
- Binary distribution consideration

### Test Architecture

**Current:** Basic XCTest setup

**Expansion Needed:**
- Mock/stub infrastructure
- Test fixtures
- Performance testing harness
- Integration test framework

---

## Conclusion

The movencoder2 architecture demonstrates:

✅ **Clear Separation of Concerns** - 5-layer architecture with well-defined boundaries  
✅ **Professional Design Patterns** - Facade, Factory, Adapter, Strategy patterns  
✅ **Robust Error Handling** - Comprehensive NSError usage and MEErrorFormatter  
✅ **Thread-Safe Design** - Proper GCD usage and atomic properties  
✅ **Security-First Approach** - Secure logging and input validation  
✅ **Performance Optimization** - Memory pooling, autoreleasepool, parallel processing  
✅ **Modern Code Practices** - Type-safe configuration and recent refactoring  

The architecture is production-ready and serves as an excellent foundation for continued development and potential framework distribution.

---

**Document Status:** Complete  
**Next Update:** As architectural changes occur
