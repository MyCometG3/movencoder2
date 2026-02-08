//
//  MEErrorFormatter.h
//  movencoder2
//
//  Lightweight central place to format NSError / FFmpeg error codes.
//
//  Copyright (C) 2025 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEErrorFormatter.h
 * @abstract Internal API - Error formatting utilities
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEErrorFormatter_h
#define MEErrorFormatter_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MEErrorFormatter : NSObject
+ (NSString *)stringFromNSError:(NSError *)error;
+ (NSString *)stringFromFFmpegCode:(int)errcode; // returns human-readable description if possible
@end

NS_ASSUME_NONNULL_END

#endif /* MEErrorFormatter_h */
