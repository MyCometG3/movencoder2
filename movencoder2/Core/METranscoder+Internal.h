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

#ifndef METranscoder_Internal_h
#define METranscoder_Internal_h

#import "MECommon.h"
#import "METranscoder.h"
#import "MEManager.h"
#import "MEInput.h"
#import "MEOutput.h"
#import "MEAudioConverter.h"
#import "SBChannel.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder ()
{
    void* controlQueueKey;
    void* processQueueKey;
}

// MARK: - private properties

@property (strong, nonatomic, nullable) AVAssetReader* assetReader;
@property (strong, nonatomic, nullable) AVAssetWriter* assetWriter;

@property (strong, nonatomic, nullable) dispatch_queue_t controlQueue;
@property (strong, nonatomic, nullable) dispatch_queue_t processQueue;

@property (strong, nonatomic) NSMutableArray<SBChannel*>* sbChannels;
@property (strong, nonatomic, nullable) NSMutableDictionary* managers;

@property (nonatomic, assign) CFAbsoluteTime timeStamp0;
@property (nonatomic, assign) CFAbsoluteTime timeStamp1;
@property (nonatomic, readonly) CFAbsoluteTime timeElapsed;

// status as atomic readwrite (override)
@property (assign) BOOL writerIsBusy; // atomic
@property (assign) BOOL finalSuccess; // atomic
@property (strong, nullable) NSError* finalError;
@property (assign) BOOL cancelled;    // atomic

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder (export) <SBChannelDelegate>

- (BOOL) exportCustomOnError:(NSError * _Nullable * _Nullable)error;
- (void) cancelExportCustom;

// MARK: - callback support

- (void) rwDidStarted;
- (void) rwDidFinished;
- (void) didReadBuffer:(CMSampleBufferRef)buffer from:(SBChannel*)channel;

// MARK: - utility methods

- (BOOL) post:(NSString*)description
       reason:(NSString*)failureReason
         code:(NSInteger)result
           to:(NSError**)error;
- (BOOL) prepareRW;
- (BOOL) hasVideoMEManagers;
- (BOOL) hasAudioMEConverters;
- (CFAbsoluteTime) timeElapsed;
- (void) cleanupTemporaryFilesForOutput:(NSURL*)outputURL;

// MARK: - refactored helper steps (export pipeline)
- (BOOL)me_prepareExportSession:(NSError * _Nullable * _Nullable)error useME:(BOOL*)useME useAC:(BOOL*)useAC;
- (BOOL)me_configureWriterAndPrepareChannelsWithMovie:(AVMutableMovie*)mov useME:(BOOL)useME useAC:(BOOL)useAC error:(NSError * _Nullable * _Nullable)error;
- (BOOL)me_startIOAndWaitWithReader:(AVAssetReader*)ar writer:(AVAssetWriter*)aw finish:(BOOL*)finish error:(NSError * _Nullable * _Nullable)error;
- (void)me_finalizeSessionWithFinish:(BOOL)finish error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder (prepareChannels)

@property (nonatomic, readonly) uint32_t audioFormatID;
@property (nonatomic, readonly) uint32_t videoFormatID;

- (void) prepareCopyChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw of:(AVMediaType)type;
- (void) prepareOtherMediaChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

// MARK: -

- (void) prepareAudioMediaChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;
- (void) prepareAudioMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

// MARK: -

- (BOOL) hasFieldModeSupportOf:(AVMovieTrack*)track;
- (void) addDecommpressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting;
- (NSMutableDictionary<NSString*,id>*) videoCompressionSettingFor:(AVMovieTrack *)track;

- (void) prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;
- (void) prepareVideoMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder (paramParser)

@property (nonatomic, readonly) BOOL copyOtherMedia;

@property (nonatomic, readonly) BOOL audioEncode;
@property (nonatomic, readonly) NSString* audioFourcc;
@property (nonatomic, readonly) int audioBitRate;
@property (nonatomic, readonly) int lpcmDepth;
@property (nonatomic, readonly) uint32_t audioChannelLayoutTag;

@property (nonatomic, readonly) BOOL videoEncode;
@property (nonatomic, readonly) NSString* videoFourcc;
@property (nonatomic, readonly) int videoBitRate;
@property (nonatomic, readonly) BOOL copyField;
@property (nonatomic, readonly) BOOL copyNCLC;

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

static inline NSString* keyForTrackID(CMPersistentTrackID trackID) {
    return [NSString stringWithFormat:@"trackID:%d", trackID];
}

NS_ASSUME_NONNULL_END

#endif /* METranscoder_Internal_h */
