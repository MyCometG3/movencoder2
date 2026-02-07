//
//  METranscoder.h
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

#ifndef METranscoder_h
#define METranscoder_h

@import Foundation;
@import AVFoundation;
@import VideoToolbox;
@import CoreAudio;

@class MEManager;
@class MEInput;
@class MEOutput;
@class MEAudioConverter;

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kLPCMDepthKey;       // NSNumber of int
extern NSString* const kAudioKbpsKey;       // NSNumber of float
extern NSString* const kVideoKbpsKey;       // NSNumber of float
extern NSString* const kCopyFieldKey;       // NSNumber of BOOL
extern NSString* const kCopyNCLCKey;        // NSNumber of BOOL
extern NSString* const kCopyOtherMediaKey;  // NSNumber of BOOL
extern NSString* const kVideoEncodeKey;     // NSNumber of BOOL
extern NSString* const kAudioEncodeKey;     // NSNumber of BOOL
extern NSString* const kVideoCodecKey;      // NSString representation of OSType
extern NSString* const kAudioCodecKey;      // NSString representation of OSType
extern NSString* const kAudioChannelLayoutTagKey; // NSNumber of uint32_t
extern NSString* const kAudioVolumeKey;        // NSNumber of float (dB)

typedef void (^progress_block_t)(NSDictionary* _Nonnull);

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithInput:(NSURL*) input output:(NSURL*) output;
+ (instancetype)transcoderWithInput:(NSURL*) input output:(NSURL*) output;

/* =================================================================================== */
// MARK: - public properties
/* =================================================================================== */

@property (strong, readonly) NSURL* inputURL;
@property (strong, readonly) NSURL* outputURL;
@property (strong, nonatomic, nullable) AVMutableMovie* inMovie;
@property (strong, nonatomic, nullable) AVMutableMovie* outMovie; // unused

@property (strong, nonatomic) NSMutableDictionary* param;
@property (assign, nonatomic) CMTime startTime;
@property (assign, nonatomic) CMTime endTime;

@property (nonatomic) BOOL verbose;
@property (nonatomic) int lastProgress; // for progressCallback support

// custom callback support
@property (strong, nonatomic, nullable) dispatch_queue_t callbackQueue;
@property (strong, nonatomic, nullable) dispatch_block_t startCallback;
@property (strong, nonatomic, nullable) progress_block_t progressCallback;
@property (strong, nonatomic, nullable) dispatch_block_t completionCallback;

// status as atomic readonly
@property (assign, readonly) BOOL writerIsBusy; // atomic
@property (assign, readonly) BOOL finalSuccess; // atomic
@property (strong, readonly, nullable) NSError* finalError; // atomic
@property (assign, readonly) BOOL cancelled;    // atomic

/* =================================================================================== */
// MARK: - public methods
/* =================================================================================== */

/**
 Register MEManager for specified trackID

 @param meManager MEManager
 @param trackID trackID
 */
- (void) registerMEManager:(MEManager*)meManager forTrackID:(CMPersistentTrackID)trackID;

/**
 Register MEAudioConverter for specified trackID

 @param meAudioConverter MEAudioConverter
 @param trackID trackID
 */
- (void) registerMEAudioConverter:(MEAudioConverter*)meAudioConverter forTrackID:(CMPersistentTrackID)trackID;

/**
 Start export asynchronously
 */
- (void) startAsync;


/**
 Cancel export session
 */
- (void) cancelAsync;

@end

NS_ASSUME_NONNULL_END

#endif /* METranscoder_h */
