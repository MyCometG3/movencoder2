//
//  MEManager.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEManager.h
 * @abstract Internal API - Video processing coordinator for filter/encoder pipelines
 * @discussion
 * MEManager coordinates the video filter and encoder pipelines (Processing Layer).
 * IO responsibilities are handled by IO layer classes (MEInput/MEOutput/SBChannel).
 * Methods that mimic AVAssetReader/Writer are provided as internal bridge APIs
 * to interact with IO adapters; they are not intended for direct external use.
 * Use METranscoder for public transcoding operations.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEManager_h
#define MEManager_h

@import Foundation;
@import AVFoundation;
@import CoreMedia;

@class MEFilterPipeline;
@class MEEncoderPipeline;
@class MESampleBufferFactory;

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

/**
 * Filter pipeline component for video filtering operations
 */
@property (nonatomic, strong, readonly) MEFilterPipeline *filterPipeline;

/**
 * Encoder pipeline component for video encoding operations
 */
@property (nonatomic, strong, readonly) MEEncoderPipeline *encoderPipeline;

/**
 * Sample buffer factory component for creating sample buffers
 */
@property (nonatomic, strong, readonly) MESampleBufferFactory *sampleBufferFactory;

/* =================================================================================== */
// MARK: - for MEInput; queue SB from previous AVAssetReaderOutput to MEInput
/* =================================================================================== */

/*
 * Internal bridge API (consumer side)
 * MEInput - Mimic AVAssetWriterInput
 * Purpose: allow SBChannel/IO adapters to feed sample buffers into the
 * processing pipeline without exposing pipeline internals.
 */

@property(nonatomic, readonly, getter=isReadyForMoreMediaData) BOOL readyForMoreMediaData;
@property(nonatomic) CMTimeScale mediaTimeScale;
@property(nonatomic) CGSize naturalSize;

// Internal alias methods (non-breaking, for IO adapters clarity)
- (BOOL)appendSampleBufferInternal:(CMSampleBufferRef)sb;
- (BOOL)isReadyForMoreMediaDataInternal;
- (void)markAsFinishedInternal;
- (void)requestMediaDataWhenReadyOnQueueInternal:(dispatch_queue_t)queue usingBlock:(RequestHandler)block;
- (CMTimeScale)mediaTimeScaleInternal;
- (void)setMediaTimeScaleInternal:(CMTimeScale)mediaTimeScale;
- (CGSize)naturalSizeInternal;
- (void)setNaturalSizeInternal:(CGSize)naturalSize;

/* =================================================================================== */
// MARK: - for MEOutput; queue SB from MEOutput to next AVAssetWriterInput
/* =================================================================================== */

/*
 * Internal bridge API (producer side)
 * MEOutput - Mimic AVAssetReaderOutput
 * Purpose: allow SBChannel/IO adapters to pull processed sample buffers
 * from the pipeline in an AVAssetReader-like fashion.
 */

// Internal alias methods (non-breaking, for IO adapters clarity)
- (nullable CMSampleBufferRef)copyNextSampleBufferInternal CF_RETURNS_RETAINED;
- (AVMediaType)mediaTypeInternal;

@end

NS_ASSUME_NONNULL_END

#endif /* MEManager_h */
