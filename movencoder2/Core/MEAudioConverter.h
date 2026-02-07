//
//  MEAudioConverter.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2026 MyCometG3. All rights reserved.
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

/**
 * @header MEAudioConverter.h
 * @abstract Internal API - Audio processing coordinator
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
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

/* MEInput - Mimic AVAssetWriterInput */

- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sb;
@property(nonatomic, readonly, getter=isReadyForMoreMediaData) BOOL readyForMoreMediaData;
- (void)markAsFinished;
- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block;
@property(nonatomic) CMTimeScale mediaTimeScale;

/* =================================================================================== */
// MARK: - for MEOutput; queue SB from MEAudioConverter to next AVAssetWriterInput
/* =================================================================================== */

/* MEOutput - Mimic AVAssetReaderOutput */

- (nullable CMSampleBufferRef)copyNextSampleBuffer CF_RETURNS_RETAINED;
@property(nonatomic, readonly) AVMediaType mediaType;

@end

NS_ASSUME_NONNULL_END

#endif /* MEAudioConverter_h */
