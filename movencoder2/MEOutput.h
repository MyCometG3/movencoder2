//
//  MEOutput.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/24.
//  Copyright © 2018-2020 MyCometG3. All rights reserved.
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
