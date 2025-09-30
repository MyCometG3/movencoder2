//
//  MEErrorFormatter.m
//  movencoder2
//
//  Centralized error formatting (Objective-C + FFmpeg).
//
//  This file is part of movencoder2 (GPLv2 or later).
//

#import "MEErrorFormatter.h"
#import "MESecureLogging.h"

#ifdef __cplusplus
extern "C" {
#endif
#include <libavutil/error.h>
#ifdef __cplusplus
}
#endif

@implementation MEErrorFormatter

+ (NSString *)stringFromNSError:(NSError *)error {
    if (!error) return @"(nil error)";
    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"%@ (domain=%@ code=%ld)", error.localizedDescription ?: @"(no description)", error.domain, (long)error.code];
    if (error.localizedFailureReason) {
        [msg appendFormat:@" reason=%@", error.localizedFailureReason];
    }
    if (error.userInfo.count) {
        [msg appendString:@" userInfo={"]; BOOL first=YES; for (id k in error.userInfo) { if(!first) [msg appendString:@", "]; first=NO; [msg appendFormat:@"%@=%@", k, error.userInfo[k]]; } [msg appendString:@"}"]; }
    return msg;
}

+ (NSString *)stringFromFFmpegCode:(int)errcode {
    if (errcode >= 0) return [NSString stringWithFormat:@"ffmpeg-ok:%d", errcode];
    char buf[128] = {0};
    int ret = av_strerror(errcode, buf, sizeof(buf));
    if (ret == 0) {
        return [NSString stringWithFormat:@"ffmpeg:%d (%s)", errcode, buf];
    }
    return [NSString stringWithFormat:@"ffmpeg:%d (unknown)", errcode];
}

@end
