//
//  METranscodeConfiguration.h
//  movencoder2
//
//  Created by OpenCode.
//
//  This is a lightweight configuration object used internally by
//  METranscoder to consolidate encoding parameters, time range,
//  logging settings, and callbacks without breaking existing APIs.
//

#ifndef METranscodeConfiguration_h
#define METranscodeConfiguration_h

// Use traditional #import to avoid module requirement warnings
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// Define a local progress block type to avoid header dependency
typedef void (^MEProgressBlock)(NSDictionary* _Nonnull);

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MELogLevel) {
    MELogLevelSilent = 0,
    MELogLevelError  = 1,
    MELogLevelInfo   = 2,
    MELogLevelDebug  = 3,
};

@interface METranscodeConfiguration : NSObject

// Encoding parameters (legacy-compatible key/value dictionary)
@property (strong, nonatomic) NSMutableDictionary* encodingParams;

// Consolidated time range
@property (assign, nonatomic) CMTimeRange timeRange;

// Logging settings
@property (assign, nonatomic) BOOL verbose;
@property (assign, nonatomic) MELogLevel logLevel;

// Callback settings
@property (strong, nonatomic, nullable) dispatch_queue_t callbackQueue;
@property (strong, nonatomic, nullable) dispatch_block_t startCallback;
@property (strong, nonatomic, nullable) MEProgressBlock progressCallback;
@property (strong, nonatomic, nullable) dispatch_block_t completionCallback;

@end

NS_ASSUME_NONNULL_END

#endif /* METranscodeConfiguration_h */
