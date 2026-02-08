//
//  MEAudioConverter.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEAudioConverter.h
 * @abstract Internal API - Audio processing coordinator (conversion and AAC encoding)
 * @discussion
 * MEAudioConverter coordinates audio format/layout/bit-depth conversion and AAC encoding.
 * IO responsibilities are handled by IO layer classes (MEInput/MEOutput/SBChannel).
 * Methods that mimic AVAssetReader/Writer are provided as internal bridge APIs to
 * interact with IO adapters; they are not intended for direct external use.
 * Use METranscoder for public transcoding operations.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEAudioConverter_h
#define MEAudioConverter_h

@import Foundation;
@import AVFoundation;
@import CoreAudio;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

typedef void (^RequestHandler)(void);

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEAudioConverter : NSObject

/**
 True if MEAudioConverter got failed. (atomic)
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
 Audio format settings dictionary
 */
@property (nonatomic, strong, nullable) NSMutableDictionary* audioSettings;
/**
 Format Description Extensions dictionary from "Source Movie's Track".
 */
@property (nonatomic, strong, nullable) __attribute__((NSObject)) CFDictionaryRef sourceExtensions;
/**
 Source and destination audio formats for conversion
 */
@property (nonatomic, strong, nullable) AVAudioFormat* sourceFormat;
@property (nonatomic, strong, nullable) AVAudioFormat* destinationFormat;
/**
 Start and end times for progress calculation
 */
@property (nonatomic) CMTime startTime;
@property (nonatomic) CMTime endTime;

@property (nonatomic) BOOL verbose;

/**
 Volume/gain adjustment in dB. Set to 0.0 for no adjustment.
 Valid range: -10.0 to +10.0 dB
 */
@property (nonatomic) double volumeDb;

/**
 Maximum input buffer count to queue.
 */
@property (nonatomic) NSUInteger maxInputBufferCount;

/* =================================================================================== */
// MARK: - for MEInput; queue SB from previous AVAssetReaderOutput to MEAudioConverter
/* =================================================================================== */

/*
 * Internal bridge API (consumer side)
 * MEInput - Mimic AVAssetWriterInput
 * Purpose: allow SBChannel/IO adapters to feed sample buffers into the
 * audio processing pipeline without exposing converter internals.
 */

- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sb;
/** Internal alias forwarding to appendSampleBuffer: */
- (BOOL)appendSampleBufferInternal:(CMSampleBufferRef)sb;
@property(nonatomic, readonly, getter=isReadyForMoreMediaData) BOOL readyForMoreMediaData;
/** Internal alias for readiness check */
- (BOOL)isReadyForMoreMediaDataInternal;
- (void)markAsFinished;
/** Internal alias forwarding to markAsFinished */
- (void)markAsFinishedInternal;
- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block;
/** Internal alias forwarding to requestMediaDataWhenReadyOnQueue:usingBlock: */
- (void)requestMediaDataWhenReadyOnQueueInternal:(dispatch_queue_t)queue usingBlock:(RequestHandler)block;
@property(nonatomic) CMTimeScale mediaTimeScale;
/** Internal aliases for mediaTimeScale */
- (CMTimeScale)mediaTimeScaleInternal;
- (void)setMediaTimeScaleInternal:(CMTimeScale)mediaTimeScale;

/* =================================================================================== */
// MARK: - for MEOutput; queue SB from MEAudioConverter to next AVAssetWriterInput
/* =================================================================================== */

/* MEOutput - Mimic AVAssetReaderOutput */

- (nullable CMSampleBufferRef)copyNextSampleBuffer CF_RETURNS_RETAINED;
/** Internal alias forwarding to copyNextSampleBuffer */
- (nullable CMSampleBufferRef)copyNextSampleBufferInternal CF_RETURNS_RETAINED;
@property(nonatomic, readonly) AVMediaType mediaType;
/** Internal alias for mediaType */
- (AVMediaType)mediaTypeInternal;

@end

NS_ASSUME_NONNULL_END

#endif /* MEAudioConverter_h */
