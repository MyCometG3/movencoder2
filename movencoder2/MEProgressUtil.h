//
//  MEProgressUtil.h
//  movencoder2
//
//  Utility extracted from METranscoder for progress calculation.
//
//  Copyright © 2025.
//

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
