//
//  MEProgressUtil.m
//  movencoder2
//
//  Progress calculation helper.
//

#import "MEProgressUtil.h"

@implementation MEProgressUtil

+ (float)progressPercentForSampleBuffer:(CMSampleBufferRef)buffer
                               start:(CMTime)start
                                 end:(CMTime)end
{
    if (!buffer) return 0.0f;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(buffer);
    CMTime dur = CMSampleBufferGetDuration(buffer);
    if (CMTIME_IS_NUMERIC(dur)) {
        pts = CMTimeAdd(pts, dur);
    }
    if (!CMTIME_IS_NUMERIC(start) || !CMTIME_IS_NUMERIC(end)) return 0.0f;
    Float64 offsetSec = CMTimeGetSeconds(CMTimeSubtract(pts, start));
    Float64 lenSec = CMTimeGetSeconds(CMTimeSubtract(end, start));
    if (lenSec <= 0.0) return 0.0f;
    Float64 progress = offsetSec / lenSec;
    if (progress < 0.0) progress = 0.0;
    if (progress > 1.0) progress = 1.0;
    return (float)(progress * 100.0);
}

@end
