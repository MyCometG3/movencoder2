# Migration Guide: Public API Adoption

**Last Updated:** February 2026

---

## Overview

This guide helps developers migrate from using internal APIs (if they were doing so) to the new public API surface. The public API provides a stable, well-documented interface suitable for long-term use.

---

## Why Migrate?

### Benefits of Public API

✅ **Stability** - Backward compatibility guarantees  
✅ **Documentation** - Comprehensive docs and examples  
✅ **Support** - Public APIs are officially supported  
✅ **Future-proof** - Safe across library updates  
✅ **Framework ready** - Designed for framework distribution  

### Risks of Internal APIs

⚠️ **No stability guarantee** - May change without notice  
⚠️ **Breaking changes** - Updates may break your code  
⚠️ **Limited documentation** - Internal docs for maintainers only  
⚠️ **No support** - Not intended for external use  

---

## Migration Checklist

### Pre-Migration Assessment

- [ ] Identify all internal API usage in your codebase
- [ ] Review public API documentation ([API_GUIDELINES.md](API_GUIDELINES.md))
- [ ] Plan migration strategy (all at once vs. incremental)
- [ ] Set up test coverage for transcoding functionality
- [ ] Create backup of current working code

### Migration Steps

- [ ] Update imports to use umbrella header
- [ ] Replace internal API calls with public equivalents
- [ ] Update error handling if needed
- [ ] Test thoroughly with representative media files
- [ ] Update documentation and code comments
- [ ] Remove any internal header imports

### Post-Migration Validation

- [ ] Verify all functionality works as expected
- [ ] Check for memory leaks (run Instruments)
- [ ] Performance test with large files
- [ ] Test edge cases and error conditions
- [ ] Update team documentation

---

## Common Migration Patterns

### 1. Header Imports

#### Before (Internal)
```objective-c
#import "METranscoder.h"
#import "MEVideoEncoderConfig.h"
#import "MEManager.h"           // ❌ Internal
#import "MEAudioConverter.h"    // ❌ Internal
#import "MEUtils.h"             // ❌ Internal
```

#### After (Public)
```objective-c
#import <MovEncoder2/MovEncoder2.h>
// That's it! Umbrella header includes all public APIs
```

---

### 2. Direct MEManager Usage

If you were directly using `MEManager` for video encoding:

#### Before (Internal - Don't do this)
```objective-c
#import "MEManager.h"

MEManager *manager = [[MEManager alloc] initWith:readerOutput
                                               to:writerInput
                                             size:videoSize];
[manager setupMEEncoderWith:encoderSettings size:videoSize];
// Manual pipeline management...
```

#### After (Public - Recommended)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL
                                                        output:outputURL];

transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"avc1",
    kVideoKbpsKey: @5000
} mutableCopy];

[transcoder startAsync];
```

**Rationale:** `METranscoder` provides a high-level interface that manages `MEManager` internally, handling all the complexity for you.

---

### 3. Direct MEAudioConverter Usage

If you were using `MEAudioConverter` directly:

#### Before (Internal - Don't do this)
```objective-c
#import "MEAudioConverter.h"

MEAudioConverter *converter = [[MEAudioConverter alloc] initWith:readerOutput
                                                               to:writerInput];
// Manual audio conversion setup...
```

#### After (Public - Recommended)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL
                                                        output:outputURL];

transcoder.param = [@{
    kAudioEncodeKey: @YES,
    kAudioCodecKey: @"aac ",
    kAudioKbpsKey: @256,
    kLPCMDepthKey: @16
} mutableCopy];

[transcoder startAsync];
```

**Rationale:** Audio conversion is handled automatically by `METranscoder` based on configuration.

---

### 4. Progress Calculation

If you were using `MEProgressUtil` directly:

#### Before (Internal - Don't do this)
```objective-c
#import "MEProgressUtil.h"

float percent = [MEProgressUtil progressPercentForSampleBuffer:buffer
                                                         start:startTime
                                                           end:endTime];
NSLog(@"Progress: %.1f%%", percent);
```

#### After (Public - Recommended)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

transcoder.progressCallback = ^(NSDictionary *info) {
    NSNumber *percent = info[kProgressPercentKey];
    NSLog(@"Progress: %.1f%%", percent.floatValue);
};
```

**Rationale:** Progress monitoring is built into `METranscoder` and delivered via callbacks.

---

### 5. Direct Pipeline Access

If you were accessing encoder/filter pipelines directly:

#### Before (Internal - Don't do this)
```objective-c
#import "MEEncoderPipeline.h"
#import "MEFilterPipeline.h"

MEEncoderPipeline *encoder = [[MEEncoderPipeline alloc] initWithConfig:config size:size];
CVPixelBufferRef encoded = [encoder encode:pixelBuffer error:&error];

MEFilterPipeline *filter = [[MEFilterPipeline alloc] initWithFilterString:filterString
                                                              sourceSize:size];
CVPixelBufferRef filtered = [filter filter:pixelBuffer error:&error];
```

#### After (Public - Recommended)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

// Configure transcoder with encoding and filtering settings
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"libx264",
    kVideoKbpsKey: @5000
    // Filter settings would be configured here as well
} mutableCopy];

[transcoder startAsync];
```

**Rationale:** Pipeline components are internal implementation details. `METranscoder` coordinates all pipeline operations.

---

### 6. Configuration Dictionaries

If you were using internal configuration constants:

#### Before (Internal - Mixed)
```objective-c
#import "MEManager.h"  // ❌ Internal constants

NSDictionary *config = @{
    kMEVECodecNameKey: @"libx264",      // ❌ Internal
    kMEVECodecFrameRateKey: @(frameRate),  // ❌ Internal
    kMEVECodecBitRateKey: @5000000      // ❌ Internal
};
```

#### After (Public - Recommended)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

transcoder.param = [@{
    kVideoEncodeKey: @YES,              // ✅ Public
    kVideoCodecKey: @"libx264",         // ✅ Public
    kVideoKbpsKey: @5000                // ✅ Public (in kbps)
} mutableCopy];
```

**Rationale:** Public API uses consistent, documented configuration keys.

---

### 7. Error Handling

If you were using internal error formatting:

#### Before (Internal - Don't do this)
```objective-c
#import "MEErrorFormatter.h"

NSString *errorMsg = [MEErrorFormatter stringFromFFmpegCode:errcode];
NSLog(@"Error: %@", errorMsg);
```

#### After (Public - Recommended)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

transcoder.completionCallback = ^{
    if (!transcoder.finalSuccess) {
        NSError *error = transcoder.finalError;
        NSLog(@"Error: %@", error.localizedDescription);

        // Use standard NSError handling
        if (error.userInfo[NSUnderlyingErrorKey]) {
            NSLog(@"Underlying: %@", error.userInfo[NSUnderlyingErrorKey]);
        }
    }
};
```

**Rationale:** Errors are surfaced through standard `NSError` objects via the public API.

---

### 8. Logging

If you were using internal logging:

#### Before (Internal - Don't do this)
```objective-c
#import "MESecureLogging.h"

SecureLogf(@"Processing frame %d", frameNumber);
SecureDebugLog(@"Debug info");
```

#### After (Public - Recommended)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

// Use standard logging
NSLog(@"Processing frame %d", frameNumber);

// Or your preferred logging framework
// [MyLogger logWithFormat:@"Processing frame %d", frameNumber];
```

**Rationale:** Internal logging is for library implementation. Use standard logging in your code.

---

## Type-Safe Configuration Migration

If you were parsing configuration strings manually:

#### Before (Manual Parsing)
```objective-c
NSString *configString = @"c=libx264;r=30000:1001;b=5M";
// Manual parsing code...
NSDictionary *config = [self parseConfigString:configString];
```

#### After (Type-Safe)
```objective-c
#import <MovEncoder2/MovEncoder2.h>

// Use MEVideoEncoderConfig for parsing
NSDictionary *dict = @{
    @"c": @"libx264",
    @"r": @"30000:1001",
    @"b": @"5M"
};

NSError *error = nil;
MEVideoEncoderConfig *config = [MEVideoEncoderConfig configFromLegacyDictionary:dict
                                                                           error:&error];

if (config) {
    // Access properties type-safely
    NSLog(@"Codec: %@", config.rawCodecName);
    NSLog(@"Frame rate: %f fps", 1.0 / CMTimeGetSeconds(config.frameRate));
    NSLog(@"Bitrate: %ld", (long)config.bitRate);
}
```

---

## Framework Integration Migration

### Before (Source Integration)

If you were including source files directly:

```
MyApp/
├── movencoder2/
│   ├── Core/
│   ├── Pipeline/
│   └── ... (all source files)
└── MyApp files...
```

Build settings:
- Header search paths pointing to all subdirectories
- All source files compiled into your target

### After (Framework Integration)

Use the movencoder2 framework:

```
MyApp/
├── Frameworks/
│   └── MovEncoder2.framework/
└── MyApp files...
```

Build settings:
- Link against MovEncoder2.framework
- Import via `#import <MovEncoder2/MovEncoder2.h>`
- Only public headers visible

See [XCODE_PROJECT_SETUP.md](XCODE_PROJECT_SETUP.md) for detailed framework setup.

---

## Incremental Migration Strategy

### Phase 1: Preparation (Week 1)
1. Add comprehensive tests for existing functionality
2. Document current usage patterns
3. Review public API documentation
4. Identify migration complexity

### Phase 2: Pilot Migration (Week 2)
1. Choose one simple use case
2. Migrate to public API
3. Test thoroughly
4. Document lessons learned

### Phase 3: Bulk Migration (Weeks 3-4)
1. Migrate remaining code
2. Update all imports
3. Test each migrated component
4. Code review

### Phase 4: Cleanup (Week 5)
1. Remove internal header imports
2. Clean up dead code
3. Update documentation
4. Final testing

### Phase 5: Validation (Week 6)
1. Regression testing
2. Performance validation
3. Memory leak testing
4. Production readiness review

---

## Testing After Migration

### Unit Tests

```objective-c
- (void)testBasicTranscoding {
    NSURL *input = [self testMovieURL];
    NSURL *output = [self temporaryOutputURL];

    METranscoder *transcoder = [[METranscoder alloc] initWithInput:input
                                                            output:output];

    transcoder.param = [@{
        kVideoEncodeKey: @YES,
        kVideoCodecKey: @"avc1",
        kVideoKbpsKey: @5000
    } mutableCopy];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Transcoding"];

    transcoder.completionCallback = ^{
        XCTAssertTrue(transcoder.finalSuccess);
        XCTAssertNil(transcoder.finalError);
        [expectation fulfill];
    };

    [transcoder startAsync];

    [self waitForExpectations:@[expectation] timeout:60.0];
}
```

### Integration Tests

```objective-c
- (void)testTranscodingPreservesMetadata {
    // Test that metadata is preserved after migration
    METranscoder *transcoder = [[METranscoder alloc] initWithInput:input output:output];

    // ... configure and run ...

    AVAsset *outputAsset = [AVAsset assetWithURL:output];
    NSArray *metadata = outputAsset.metadata;

    XCTAssertGreaterThan(metadata.count, 0);
    // Verify specific metadata items...
}
```

---

## Common Issues and Solutions

### Issue: "Undefined symbol: _kMEVECodecNameKey"

**Cause:** Using internal constant that's not in public API

**Solution:** Use public equivalent:
```objective-c
// Instead of kMEVECodecNameKey
// Use kVideoCodecKey
transcoder.param[kVideoCodecKey] = @"libx264";
```

### Issue: "Cannot find protocol declaration for 'MEManagerDelegate'"

**Cause:** Internal protocol not available in public API

**Solution:** Use callbacks instead:
```objective-c
transcoder.progressCallback = ^(NSDictionary *info) {
    // Handle progress
};
```

### Issue: "Header 'MEManager.h' not found"

**Cause:** Importing internal header

**Solution:** Use public umbrella header:
```objective-c
#import <MovEncoder2/MovEncoder2.h>
```

### Issue: "Different behavior after migration"

**Cause:** May have been relying on internal implementation details

**Solution:** Review your assumptions and test against documented public API behavior. File an issue if public API is missing needed functionality.

---

## Getting Help

If you encounter migration issues:

1. **Check documentation**
   - [API_GUIDELINES.md](API_GUIDELINES.md) - Public API reference
   - [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md) - Code examples
   - [ARCHITECTURE.md](ARCHITECTURE.md) - Architecture overview

2. **Search issues** - Check if others have encountered similar problems

3. **File an issue** - If public API is missing needed functionality

4. **Ask questions** - Use GitHub Discussions for migration help

---

## Success Criteria

Your migration is complete when:

- [ ] No internal header imports remain
- [ ] All functionality works via public API
- [ ] Tests pass with similar code coverage
- [ ] Performance is comparable or better
- [ ] Memory usage is stable
- [ ] Code is cleaner and more maintainable

---

## Additional Resources

- [API_GUIDELINES.md](API_GUIDELINES.md) - Complete public API documentation
- [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md) - Practical code examples
- [XCODE_PROJECT_SETUP.md](XCODE_PROJECT_SETUP.md) - Framework integration
- [README.md](../README.md) - Project overview

---

## Feedback

Your migration experience helps improve the public API. Please share:

- What worked well
- What was difficult
- Missing functionality
- Documentation gaps
- Suggestions for improvement

File feedback as GitHub issues or discussions.

---

**Note:** This migration guide assumes you were previously using internal APIs. If you're a new user, simply follow the [API_GUIDELINES.md](API_GUIDELINES.md) and [USAGE_EXAMPLES.md](USAGE_EXAMPLES.md).
