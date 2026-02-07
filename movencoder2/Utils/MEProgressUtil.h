//
//  MEProgressUtil.h
//  movencoder2
//
//  Utility extracted from METranscoder for progress calculation.
//
//  Copyright © 2025-2026 MyCometG3. All rights reserved.
//

/**
 * @header MEProgressUtil.h
 * @abstract Internal API - Progress calculation utilities
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 * Use progress callbacks on METranscoder for public progress monitoring.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEProgressUtil_h
#define MEProgressUtil_h

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MEProgressUtil : NSObject
+ (float)progressPercentForSampleBuffer:(CMSampleBufferRef)buffer
                               start:(CMTime)start
                                 end:(CMTime)end; // 0.0 .. 100.0
@end

NS_ASSUME_NONNULL_END

#endif /* MEProgressUtil_h */
