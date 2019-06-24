//
//  MEOutput.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//  Copyright © 2018 MyCometG3. All rights reserved.
//

/*
 * This file is part of movencoder2.
 *
 * movencoder2 is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * movencoder2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import "MEOutput.h"
#import "MEManager.h"

#ifndef ALog
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

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
        return [_meManager copyNextSampleBuffer];
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
        return _meManager.mediaType;
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
