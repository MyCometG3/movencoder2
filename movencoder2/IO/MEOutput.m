//
//  MEOutput.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEOutput.h"
#import "MEManager.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEOutput

- (instancetype)initWithManager:(MEManager*)manager
{
    if (self = [super init]) {
        _meManager = manager;
    }
    return self;
}

+ (instancetype)outputWithManager:(MEManager*)manager
{
    return [[self alloc] initWithManager:manager];
}

- (instancetype)initWithAssetReaderOutput:(AVAssetReaderOutput*) arOutput
{
    if (self = [super init]) {
        _arOutput = arOutput;
    }
    return self;
}

+ (instancetype)outputWithAssetReaderOutput:(AVAssetReaderOutput*) arOutput
{
    return [[self alloc] initWithAssetReaderOutput:arOutput];
}

/* =================================================================================== */
// MARK: - AVAssetReaderOutput
/* =================================================================================== */

- (nullable CMSampleBufferRef)copyNextSampleBuffer
{
    // This is synchronous call
    if (_meManager)
        return [_meManager copyNextSampleBufferInternal];
    else if (_arOutput)
        return [_arOutput copyNextSampleBuffer];
    else
        return nil;
}

- (BOOL)alwaysCopiesSampleData
{
    if (_meManager)
        return TRUE;
    else if (_arOutput)
        return _arOutput.alwaysCopiesSampleData;
    else
        return TRUE;
}

- (void)setAlwaysCopiesSampleData:(BOOL)alwaysCopiesSampleData
{
    if (_meManager)
        ;
    else if (_arOutput)
        [_arOutput setAlwaysCopiesSampleData:alwaysCopiesSampleData];
    else
        ;
}

- (nullable AVMediaType) mediaType
{
    if (_meManager)
        return _meManager.mediaTypeInternal;
    else if (_arOutput)
        return _arOutput.mediaType;
    else
        return nil;
}

- (void)markConfigurationAsFinal
{
    if (_meManager)
        ; // Ignore this
    else if (_arOutput)
        [_arOutput markConfigurationAsFinal];
    else
        ;
}

- (void)resetForReadingTimeRanges:(NSArray<NSValue *> *)timeRanges
{
    if (_meManager)
        ; // Ignore this
    else if (_arOutput)
        [_arOutput resetForReadingTimeRanges:timeRanges];
    else
        ;
}

- (BOOL) supportsRandomAccess
{
    if (_meManager)
        return FALSE;
    else if (_arOutput)
        return [_arOutput supportsRandomAccess];
    else
        return FALSE;
}

- (void) setSupportsRandomAccess:(BOOL)supportsRandomAccess
{
    if (_meManager)
        ;
    else if (_arOutput)
        [_arOutput setSupportsRandomAccess:supportsRandomAccess];
    else
        ;
}

@end

NS_ASSUME_NONNULL_END
