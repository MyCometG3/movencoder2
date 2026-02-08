//
//  MEInput.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEInput.h"
#import "MEManager.h"

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
        return [_meManager appendSampleBufferInternal:sampleBuffer];
    else if (_awInput)
        return [_awInput appendSampleBuffer:sampleBuffer];
    else
        return false;
}

- (BOOL)isReadyForMoreMediaData
{
    if (_meManager)
        return [_meManager isReadyForMoreMediaDataInternal];
    else if (_awInput)
        return [_awInput isReadyForMoreMediaData];
    else
        return false;
}

- (void)markAsFinished
{
    if (_meManager)
        [_meManager markAsFinishedInternal];
    else if (_awInput)
        [_awInput markAsFinished];
    else
        ;
}

- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block
{
    if (_meManager)
        [_meManager requestMediaDataWhenReadyOnQueueInternal:queue usingBlock:block];
    else if (_awInput)
        [_awInput requestMediaDataWhenReadyOnQueue:queue usingBlock:block];
    else
        ;
}

- (AVMediaType) mediaType
{
    if (_meManager)
        return [_meManager mediaTypeInternal];
    else if (_awInput)
        return [_awInput mediaType];
    else
        return AVMediaTypeVideo;
}

- (CMTimeScale) mediaTimeScale
{
    if (_meManager)
        return [_meManager mediaTimeScaleInternal];
    else if (_awInput)
        return [_awInput mediaTimeScale];
    else
        return 0;
}

- (void) setMediaTimeScale:(CMTimeScale)mediaTimeScale
{
    if (_meManager)
        [_meManager setMediaTimeScaleInternal:mediaTimeScale];
    else if (_awInput)
        [_awInput setMediaTimeScale:mediaTimeScale];
    else
        ;
}

- (CGSize) naturalSize
{
    if (_meManager)
        return [_meManager naturalSizeInternal];
    else if (_awInput)
        return [_awInput naturalSize];
    else
        return CGSizeZero;
}

- (void) setNaturalSize:(CGSize)naturalSize
{
    if (_meManager)
        [_meManager setNaturalSizeInternal:naturalSize];
    else if (_awInput)
        [_awInput setNaturalSize:naturalSize];
    else
        ;
}

@end

NS_ASSUME_NONNULL_END
