//
//  METranscoder.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
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

@property (strong, nonatomic) dispatch_queue_t controlQueue;
@property (strong, nonatomic) dispatch_queue_t processQueue;

@property (strong, nonatomic) NSMutableArray<SBChannel*>*sbChannels;
@property (strong, nonatomic, nullable) NSMutableDictionary* managers;

@property (nonatomic, assign) CFAbsoluteTime timeStamp0;
@property (nonatomic, assign) CFAbsoluteTime timeStamp1;
@property (nonatomic, readonly) CFAbsoluteTime timeElapsed;

// status as atomic readwrite (override)
@property (assign) BOOL writerIsBusy; // atomic
@property (assign) BOOL finalSuccess; // atomic
@property (strong, nonatomic, nullable) NSError* finalError;
@property (assign) BOOL cancelled;    // atomic

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder (export) <SBChannelDelegate>

- (BOOL) post:(NSString*)description
       reason:(NSString*)failureReason
         code:(NSInteger)result
           to:(NSError**)error;

- (BOOL) exportCustomOnError:(NSError * _Nullable * _Nullable)error;
- (void) cancelExportCustom;

- (void) rwDidStarted;
- (void) rwDidFinished;
- (void) didReadBuffer:(CMSampleBufferRef)buffer from:(SBChannel*)channel;

- (BOOL) hasVideoMEManagers;
- (BOOL) hasAudioMEConverters;

- (void) cleanupTemporaryFilesForOutput:(NSURL*)outputURL;

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

#endif /* METranscoder_h */
