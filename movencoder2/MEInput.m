//
//  MEInput.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//  Copyright © 2018-2021 MyCometG3. All rights reserved.
//

/*
 * This file is part of movencoder2.
 *
 * movencoder2 is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * movencoder2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with movencoder2; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

#import "MEInput.h"
#import "MEManager.h"

#ifndef ALog
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEInput

- (instancetype)initWithManager:(MEManager *)manager
{
    if (self = [super init]) {
        _meManager = manager;
    }
    return self;
}

+ (instancetype)inputWithManager:(MEManager *)manager
{
    return [[self alloc] initWithManager:manager];
}

- (instancetype)initWithAssetWriterInput:(AVAssetWriterInput*) awInput
{
    if (self = [super init]) {
        _awInput = awInput;
    }
    return self;
}

+ (instancetype)inputWithAssetWriterInput:(AVAssetWriterInput*) awInput
{
    return [[self alloc] initWithAssetWriterInput:awInput];
}

/* =================================================================================== */
// MARK: - AVAssetWriterInput
/* =================================================================================== */

- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (_meManager)
        return [_meManager appendSampleBuffer:sampleBuffer];
    else if (_awInput)
        return [_awInput appendSampleBuffer:sampleBuffer];
    else
        return false;
}

- (BOOL)isReadyForMoreMediaData
{
    if (_meManager)
        return [_meManager isReadyForMoreMediaData];
    else if (_awInput)
        return [_awInput isReadyForMoreMediaData];
    else
        return false;
}

- (void)markAsFinished
{
    if (_meManager)
        [_meManager markAsFinished];
    else if (_awInput)
        [_awInput markAsFinished];
    else
        ;
}

- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block
{
    if (_meManager)
        [_meManager requestMediaDataWhenReadyOnQueue:queue usingBlock:block];
    else if (_awInput)
        [_awInput requestMediaDataWhenReadyOnQueue:queue usingBlock:block];
    else
        ;
}

- (AVMediaType) mediaType
{
    if (_meManager)
        return [_meManager mediaType];
    else if (_awInput)
        return [_awInput mediaType];
    else
        return AVMediaTypeVideo;
}

- (CMTimeScale) mediaTimeScale
{
    if (_meManager)
        return [_meManager mediaTimeScale];
    else if (_awInput)
        return [_awInput mediaTimeScale];
    else
        return 0;
}

- (void) setMediaTimeScale:(CMTimeScale)mediaTimeScale
{
    if (_meManager)
        [_meManager setMediaTimeScale:mediaTimeScale];
    else if (_awInput)
        [_awInput setMediaTimeScale:mediaTimeScale];
    else
        ;
}

- (CGSize) naturalSize
{
    if (_meManager)
        return [_meManager naturalSize];
    else if (_awInput)
        return [_awInput naturalSize];
    else
        return CGSizeZero;
}

- (void) setNaturalSize:(CGSize)naturalSize
{
    if (_meManager)
        [_meManager setNaturalSize:naturalSize];
    else if (_awInput)
        [_awInput setNaturalSize:naturalSize];
    else
        ;
}

@end

NS_ASSUME_NONNULL_END
