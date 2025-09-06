//
//  MEManager.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//  Copyright © 2018-2023 MyCometG3. All rights reserved.
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

#ifndef MEManager_h
#define MEManager_h

@import Foundation;
@import AVFoundation;
@import CoreMedia;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kMEVECodecNameKey;       // ffmpeg -c:v libx264
extern NSString* const kMEVECodecOptionsKey;    // NSDictionary of AVOptions for codec ; ffmpeg -h encoder=libx264
extern NSString* const kMEVEx264_paramsKey;     // NSString ; ffmpeg -x264-params "x264option_strings"
extern NSString* const kMEVEx265_paramsKey;     // NSString ; ffmpeg -x265-params "x265option_strings"
extern NSString* const kMEVECodecFrameRateKey;  // NSValue of CMTime ; ffmpeg -r 30000:1001
extern NSString* const kMEVECodecWxHKey;        // NSValue of NSSize ; ffmpeg -s 720x480
extern NSString* const kMEVECodecPARKey;        // NSValue of NSSize ; ffmpeg -aspect 16:9
extern NSString* const kMEVFFilterStringKey;    // NSString ; ffmpeg -vf "filter_graph_strings"
extern NSString* const kMEVECodecBitRateKey;    // NSNumber ; ffmpeg -b:v 2.5M
extern NSString* const kMEVECleanApertureKey;   // NSValue of NSRect ; convert as ffmpeg -crop-left/right/top/bottom

typedef void (^RequestHandler)(void);

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEManager : NSObject

/**
 True if MEManager got failed. (atomic)
 */
@property (readonly) BOOL failed;                       // atomic
/**
 MEInput status as AVAssetWriterStatus. (atomic)
 */
@property (readonly) AVAssetWriterStatus writerStatus;  // atomic, for MEInput
/**
 MEOutput status as AVAssetReaderStatus. (atomic)
 */
@property (readonly) AVAssetReaderStatus readerStatus;  // atomic, for MEOutput
/**
 AVFilter String
 */
@property (nonatomic, strong, nullable) NSString *videoFilterString;
/**
 AVCocec settings dictionary
 */
@property (nonatomic, strong, nullable) NSMutableDictionary* videoEncoderSetting;
/**
 Format Description Extensions dictionary from "Source Movie's Track".
 */
@property (nonatomic, strong, nullable) __attribute__((NSObject)) CFDictionaryRef sourceExtensions;
/**
 Start output after specified delay
 */
@property (nonatomic) float initialDelayInSec;
@property (nonatomic) BOOL verbose;
@property (nonatomic) int log_level;

/* =================================================================================== */
// MARK: - for MEInput; queue SB from previous AVAssetReaderOutput to MEInput
/* =================================================================================== */

/* MEInput - Mimic AVAssetWriterInput */

- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sb;
@property(nonatomic, readonly, getter=isReadyForMoreMediaData) BOOL readyForMoreMediaData;
- (void)markAsFinished;
- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block;
@property(nonatomic) CMTimeScale mediaTimeScale;
@property(nonatomic) CGSize naturalSize;

/* =================================================================================== */
// MARK: - for MEOutput; queue SB from MEOutput to next AVAssetWriterInput
/* =================================================================================== */

/* MEOutput - Mimic AVAssetReaderOutput */

- (nullable CMSampleBufferRef)copyNextSampleBuffer CF_RETURNS_RETAINED;
@property(nonatomic, readonly) AVMediaType mediaType;

@end

NS_ASSUME_NONNULL_END

#endif /* MEManager_h */
