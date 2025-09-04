//
//  MEAudioConverter.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
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

#ifndef MEAudioConverter_h
#define MEAudioConverter_h

@import Foundation;
@import AVFoundation;
@import CoreAudio;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kProgressMediaTypeKey;   // NSString
extern NSString* const kProgressTagKey;         // NSString
extern NSString* const kProgressTrackIDKey;     // NSNumber of int
extern NSString* const kProgressPTSKey;         // NSNumber of float
extern NSString* const kProgressDTSKey;         // NSNumber of float
extern NSString* const kProgressPercentKey;     // NSNumber of float
extern NSString* const kProgressCountKey;       // NSNumber of int

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
