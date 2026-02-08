//
//  MEOutput.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEOutput.h
 * @abstract Internal API - Asset writing abstraction
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEOutput_h
#define MEOutput_h

@import Foundation;
@import AVFoundation;
@import CoreMedia;

@class MEManager;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

/*
 Similar interface to AVAssetReaderTrackOutput
 libavXX producer class
 */

NS_ASSUME_NONNULL_BEGIN

@interface MEOutput : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithManager:(MEManager*)manager;
+ (instancetype)outputWithManager:(MEManager*)manager;

- (instancetype)initWithAssetReaderOutput:(AVAssetReaderOutput*) arOutput;
+ (instancetype)outputWithAssetReaderOutput:(AVAssetReaderOutput*) arOutput;

@property(nonatomic, readonly, nullable) AVAssetReaderOutput* arOutput;
@property(nonatomic, readonly, nullable) MEManager* meManager;

/* =================================================================================== */
// MARK: - mimic AVAssetReaderOutput
/* =================================================================================== */

- (nullable CMSampleBufferRef)copyNextSampleBuffer CF_RETURNS_RETAINED;
@property(nonatomic) BOOL alwaysCopiesSampleData;
@property(nonatomic, readonly, nullable) AVMediaType mediaType;
- (void)markConfigurationAsFinal;
- (void)resetForReadingTimeRanges:(NSArray<NSValue *> *)timeRanges;
@property(nonatomic) BOOL supportsRandomAccess;

@end

NS_ASSUME_NONNULL_END

#endif /* MEOutput_h */
