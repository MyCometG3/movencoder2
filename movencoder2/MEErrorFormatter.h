//
//  MEErrorFormatter.h
//  movencoder2
//
//  Lightweight central place to format NSError / FFmpeg error codes.
//
//  This file is part of movencoder2 (GPLv2 or later).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MEErrorFormatter : NSObject
+ (NSString *)stringFromNSError:(NSError *)error;
+ (NSString *)stringFromFFmpegCode:(int)errcode; // returns human-readable description if possible
@end

NS_ASSUME_NONNULL_END
