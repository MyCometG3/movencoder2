# movencoder2 Usage Examples

**Version:** 1.0  
**Last Updated:** December 2025

---

## Quick Start

### Basic Transcoding

The simplest way to transcode a video:

```objective-c
#import <MovEncoder2/MovEncoder2.h>

NSURL *inputURL = [NSURL fileURLWithPath:@"/path/to/input.mov"];
NSURL *outputURL = [NSURL fileURLWithPath:@"/path/to/output.mov"];

METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL 
                                                        output:outputURL];

// Configure video encoding
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"avc1",
    kVideoKbpsKey: @5000
} mutableCopy];

// Start transcoding
[transcoder startAsync];

// The transcoding runs asynchronously
// Use callbacks to monitor progress and completion
```

---

## Video Encoding Examples

### H.264 Encoding (AVFoundation)

```objective-c
#import <MovEncoder2/MovEncoder2.h>

METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL output:outputURL];

// Configure H.264 encoding with AVFoundation
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"avc1",  // H.264 codec
    kVideoKbpsKey: @5000,     // 5 Mbps
    kCopyFieldKey: @YES,      // Preserve field information
    kCopyNCLCKey: @YES        // Preserve color information
} mutableCopy];

[transcoder startAsync];
```

### H.264 Encoding (libx264)

```objective-c
// Using libx264 encoder with custom options
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"libx264",
    kVideoKbpsKey: @5000,
    // Additional libx264 settings can be passed via dictionary
} mutableCopy];

[transcoder startAsync];
```

### H.265 Encoding (libx265)

```objective-c
// Using libx265 encoder
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"libx265",
    kVideoKbpsKey: @8000,  // Higher bitrate for better quality
} mutableCopy];

[transcoder startAsync];
```

---

## Audio Encoding Examples

### AAC Audio Encoding

```objective-c
transcoder.param = [@{
    kAudioEncodeKey: @YES,
    kAudioCodecKey: @"aac ",  // Note: space padding for FourCC
    kAudioKbpsKey: @256,      // 256 kbps
} mutableCopy];

[transcoder startAsync];
```

### Audio with Bit Depth Conversion

```objective-c
// Convert 32-bit audio to 16-bit
transcoder.param = [@{
    kAudioEncodeKey: @YES,
    kAudioCodecKey: @"aac ",
    kAudioKbpsKey: @192,
    kLPCMDepthKey: @16  // Target bit depth
} mutableCopy];

[transcoder startAsync];
```

### Audio Channel Layout Conversion

```objective-c
// Convert 5.1 surround to stereo
transcoder.param = [@{
    kAudioEncodeKey: @YES,
    kAudioCodecKey: @"aac ",
    kAudioKbpsKey: @256,
    kAudioChannelLayoutTagKey: @(kAudioChannelLayoutTag_Stereo)
} mutableCopy];

[transcoder startAsync];
```

### Audio Volume Adjustment

```objective-c
// Adjust audio volume (in dB)
transcoder.param = [@{
    kAudioEncodeKey: @YES,
    kAudioCodecKey: @"aac ",
    kAudioKbpsKey: @192,
    kAudioVolumeKey: @(-3.0)  // Reduce volume by 3dB
} mutableCopy];

[transcoder startAsync];
```

---

## Combined Video and Audio

### Complete Transcoding Configuration

```objective-c
METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL output:outputURL];

transcoder.param = [@{
    // Video settings
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"avc1",
    kVideoKbpsKey: @5000,
    kCopyFieldKey: @YES,
    kCopyNCLCKey: @YES,
    
    // Audio settings
    kAudioEncodeKey: @YES,
    kAudioCodecKey: @"aac ",
    kAudioKbpsKey: @256,
    kLPCMDepthKey: @16
} mutableCopy];

[transcoder startAsync];
```

---

## Progress Monitoring

### Basic Progress Callback

```objective-c
transcoder.progressCallback = ^(NSDictionary *info) {
    NSNumber *percent = info[kProgressPercentKey];
    NSLog(@"Progress: %.1f%%", percent.floatValue);
};

[transcoder startAsync];
```

### Detailed Progress Information

```objective-c
transcoder.progressCallback = ^(NSDictionary *info) {
    NSString *mediaType = info[kProgressMediaTypeKey];    // "vide" or "soun"
    NSString *tag = info[kProgressTagKey];                // Track identifier
    NSNumber *trackID = info[kProgressTrackIDKey];        // Track ID
    NSNumber *pts = info[kProgressPTSKey];                // Presentation time
    NSNumber *percent = info[kProgressPercentKey];        // Progress percentage
    NSNumber *count = info[kProgressCountKey];            // Sample count
    
    NSLog(@"[%@] Track %@: %.1f%% (%ld samples, PTS: %.2fs)",
          mediaType, trackID, percent.floatValue, count.longValue, pts.doubleValue);
};

[transcoder startAsync];
```

### Progress with Custom Queue

```objective-c
// Execute callbacks on main queue for UI updates
transcoder.callbackQueue = dispatch_get_main_queue();

transcoder.progressCallback = ^(NSDictionary *info) {
    NSNumber *percent = info[kProgressPercentKey];
    
    // Safe to update UI here
    dispatch_async(dispatch_get_main_queue(), ^{
        [progressIndicator setDoubleValue:percent.doubleValue];
        [statusLabel setStringValue:[NSString stringWithFormat:@"%.1f%%", percent.floatValue]];
    });
};

[transcoder startAsync];
```

---

## Completion Handling

### Basic Completion Callback

```objective-c
transcoder.completionCallback = ^{
    if (transcoder.finalSuccess) {
        NSLog(@"✅ Transcoding completed successfully!");
    } else {
        NSLog(@"❌ Transcoding failed: %@", transcoder.finalError);
    }
};

[transcoder startAsync];
```

### Complete Callback Chain

```objective-c
// Start callback
transcoder.startCallback = ^{
    NSLog(@"🚀 Transcoding started...");
};

// Progress callback
transcoder.progressCallback = ^(NSDictionary *info) {
    NSNumber *percent = info[kProgressPercentKey];
    NSLog(@"⏳ Progress: %.1f%%", percent.floatValue);
};

// Completion callback
transcoder.completionCallback = ^{
    if (transcoder.finalSuccess) {
        NSLog(@"✅ Transcoding completed successfully!");
        // Process output file
        [self processTranscodedFile:transcoder.outputURL];
    } else {
        NSLog(@"❌ Transcoding failed: %@", transcoder.finalError);
        // Handle error
        [self handleTranscodingError:transcoder.finalError];
    }
};

[transcoder startAsync];
```

---

## Cancellation

### Cancel Transcoding

```objective-c
// Start transcoding
[transcoder startAsync];

// Later, cancel if needed
[transcoder cancelAsync];

// Check if cancelled
if (transcoder.cancelled) {
    NSLog(@"Transcoding was cancelled by user");
}
```

### Cancel with Cleanup

```objective-c
- (void)cancelTranscoding {
    [self.transcoder cancelAsync];
    
    // Wait a bit for cleanup
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), 
                   dispatch_get_main_queue(), ^{
        if (self.transcoder.cancelled) {
            // Remove incomplete output file
            [[NSFileManager defaultManager] removeItemAtURL:self.transcoder.outputURL error:nil];
            NSLog(@"Cancelled and cleaned up partial output");
        }
    });
}
```

---

## Time Range Selection

### Transcode Specific Time Range

```objective-c
// Transcode only from 10s to 30s
transcoder.startTime = CMTimeMake(10, 1);  // 10 seconds
transcoder.endTime = CMTimeMake(30, 1);    // 30 seconds

[transcoder startAsync];
```

### Transcode First N Seconds

```objective-c
// Transcode first 60 seconds
transcoder.startTime = kCMTimeZero;
transcoder.endTime = CMTimeMake(60, 1);

[transcoder startAsync];
```

---

## Advanced Configuration

### Type-Safe Configuration (Recommended)

```objective-c
// Create type-safe encoder config
NSDictionary *legacyConfig = @{
    @"c": @"libx264",
    @"r": @"30000:1001",
    @"b": @"5M",
    @"o": @"preset=medium:profile=high:level=4.1"
};

NSError *error = nil;
MEVideoEncoderConfig *config = [MEVideoEncoderConfig configFromLegacyDictionary:legacyConfig
                                                                           error:&error];

if (config) {
    NSLog(@"Codec: %@", config.rawCodecName);
    NSLog(@"Frame rate: %.2f fps", 1.0 / CMTimeGetSeconds(config.frameRate));
    NSLog(@"Bitrate: %ld bps", (long)config.bitRate);
    
    // Check for validation issues
    if (config.issues.count > 0) {
        NSLog(@"Configuration issues: %@", config.issues);
    }
} else {
    NSLog(@"Configuration error: %@", error);
}
```

### Copy Other Media Tracks

```objective-c
// Copy subtitles, metadata, and other tracks as-is
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"avc1",
    kVideoKbpsKey: @5000,
    kCopyOtherMediaKey: @YES  // Copy non-audio/video tracks
} mutableCopy];

[transcoder startAsync];
```

---

## Error Handling

### Comprehensive Error Handling

```objective-c
METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL output:outputURL];

// Validate input
if (![[NSFileManager defaultManager] fileExistsAtPath:inputURL.path]) {
    NSLog(@"❌ Input file does not exist");
    return;
}

// Configure
transcoder.param = [@{
    kVideoEncodeKey: @YES,
    kVideoCodecKey: @"avc1",
    kVideoKbpsKey: @5000
} mutableCopy];

// Set completion handler with error checking
transcoder.completionCallback = ^{
    if (transcoder.finalSuccess) {
        NSLog(@"✅ Success!");
    } else {
        NSError *error = transcoder.finalError;
        NSLog(@"❌ Error: %@", error.localizedDescription);
        
        // Check error domain and code
        if ([error.domain isEqualToString:AVFoundationErrorDomain]) {
            NSLog(@"AVFoundation error code: %ld", (long)error.code);
        }
        
        // Check underlying errors
        NSError *underlyingError = error.userInfo[NSUnderlyingErrorKey];
        if (underlyingError) {
            NSLog(@"Underlying error: %@", underlyingError);
        }
    }
};

[transcoder startAsync];
```

---

## Command-Line Tool Integration

### CLI Wrapper Example

```objective-c
// main.m for CLI tool
#import <Foundation/Foundation.h>
#import <MovEncoder2/MovEncoder2.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "Usage: %s input output [options]\n", argv[0]);
            return 1;
        }
        
        NSString *inputPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outputPath = [NSString stringWithUTF8String:argv[2]];
        
        NSURL *inputURL = [NSURL fileURLWithPath:inputPath];
        NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
        
        METranscoder *transcoder = [[METranscoder alloc] initWithInput:inputURL 
                                                                output:outputURL];
        
        transcoder.param = [@{
            kVideoEncodeKey: @YES,
            kVideoCodecKey: @"avc1",
            kVideoKbpsKey: @5000
        } mutableCopy];
        
        __block BOOL finished = NO;
        __block int exitCode = 0;
        
        transcoder.progressCallback = ^(NSDictionary *info) {
            NSNumber *percent = info[kProgressPercentKey];
            fprintf(stderr, "\rProgress: %.1f%%", percent.floatValue);
            fflush(stderr);
        };
        
        transcoder.completionCallback = ^{
            fprintf(stderr, "\n");
            if (transcoder.finalSuccess) {
                printf("✅ Transcoding completed successfully\n");
                exitCode = 0;
            } else {
                fprintf(stderr, "❌ Transcoding failed: %s\n", 
                        transcoder.finalError.localizedDescription.UTF8String);
                exitCode = 1;
            }
            finished = YES;
        };
        
        [transcoder startAsync];
        
        // Wait for completion
        while (!finished) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode 
                                     beforeDate:[NSDate distantFuture]];
        }
        
        return exitCode;
    }
}
```

---

## Best Practices

### 1. Always Check File Existence

```objective-c
NSString *inputPath = @"/path/to/input.mov";
if (![[NSFileManager defaultManager] fileExistsAtPath:inputPath]) {
    // Handle missing file
    return;
}
```

### 2. Use Appropriate Bitrates

```objective-c
// SD (480p): 1-2 Mbps
// HD (720p): 3-5 Mbps
// Full HD (1080p): 5-10 Mbps
// 4K (2160p): 15-25 Mbps

transcoder.param[@(kVideoKbpsKey)] = @5000;  // 5 Mbps for 1080p
```

### 3. Handle Cancellation Gracefully

```objective-c
- (void)dealloc {
    if (self.transcoder && !self.transcoder.finalSuccess) {
        [self.transcoder cancelAsync];
    }
}
```

### 4. Use Completion Callbacks

```objective-c
// Always set completion callback to know when transcoding finishes
transcoder.completionCallback = ^{
    // Handle completion
};
```

### 5. Clean Up Resources

```objective-c
transcoder.completionCallback = ^{
    if (!transcoder.finalSuccess) {
        // Remove incomplete output file
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    }
    
    // Release transcoder
    self.transcoder = nil;
};
```

---

## Common Patterns

### Batch Processing

```objective-c
- (void)transcodeFiles:(NSArray<NSURL*>*)inputFiles toDirectory:(NSURL*)outputDirectory {
    __block NSUInteger currentIndex = 0;
    __block METranscoder *transcoder = nil;
    
    void (^processNext)(void) = ^{
        if (currentIndex >= inputFiles.count) {
            NSLog(@"✅ All files processed!");
            return;
        }
        
        NSURL *inputURL = inputFiles[currentIndex];
        NSString *outputName = [inputURL.lastPathComponent stringByAppendingString:@"_transcoded.mov"];
        NSURL *outputURL = [outputDirectory URLByAppendingPathComponent:outputName];
        
        transcoder = [[METranscoder alloc] initWithInput:inputURL output:outputURL];
        transcoder.param = /* ... configure ... */;
        
        transcoder.completionCallback = ^{
            NSLog(@"Completed %lu/%lu", currentIndex + 1, inputFiles.count);
            currentIndex++;
            processNext();
        };
        
        [transcoder startAsync];
    };
    
    processNext();
}
```

### Progress with NSProgress

```objective-c
@property (strong) NSProgress *progress;

- (void)startTranscoding {
    self.progress = [NSProgress progressWithTotalUnitCount:100];
    
    self.transcoder.progressCallback = ^(NSDictionary *info) {
        NSNumber *percent = info[kProgressPercentKey];
        self.progress.completedUnitCount = percent.integerValue;
    };
    
    [self.transcoder startAsync];
}
```

---

## Troubleshooting

### Problem: "Input file cannot be read"

**Solution:** Check file permissions and format support

```objective-c
NSError *error = nil;
AVAsset *asset = [AVAsset assetWithURL:inputURL];
if ([asset isReadable]) {
    // File is readable
} else {
    NSLog(@"File is not readable");
}
```

### Problem: "Encoding fails immediately"

**Solution:** Check codec availability and configuration

```objective-c
// Verify codec is available
if (![AVAssetWriter canApplyOutputSettings:videoSettings forMediaType:AVMediaTypeVideo]) {
    NSLog(@"Video settings not supported");
}
```

### Problem: "Memory usage grows during transcoding"

**Solution:** Ensure proper autorelease pool usage

```objective-c
// The library handles this internally, but if you're processing callbacks:
transcoder.progressCallback = ^(NSDictionary *info) {
    @autoreleasepool {
        // Process progress
    }
};
```

---

## See Also

- [API_GUIDELINES.md](API_GUIDELINES.md) - Complete API reference
- [XCODE_PROJECT_SETUP.md](XCODE_PROJECT_SETUP.md) - Framework integration
- [README.md](../README.md) - Project overview
