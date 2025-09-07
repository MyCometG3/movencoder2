//
//  METranscoder.m
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

#import "METranscoder+Internal.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NSString* const kLPCMDepthKey = @"lpcmDepth";
NSString* const kAudioKbpsKey = @"audioKbps";
NSString* const kVideoKbpsKey = @"videoKbps";
NSString* const kCopyFieldKey = @"copyField";
NSString* const kCopyNCLCKey = @"copyNCLC";
NSString* const kCopyOtherMediaKey = @"copyOtherMedia";
NSString* const kVideoEncodeKey = @"videoEncode";
NSString* const kAudioEncodeKey = @"audioEncode";
NSString* const kVideoCodecKey = @"videoCodec";
NSString* const kAudioCodecKey = @"audioCodec";
NSString* const kAudioChannelLayoutTagKey = @"audioChannelLayoutTag";

static const char* const kControlQueueLabel = "movencoder.controlQueue";
static const char* const kProcessQueueLabel = "movencoder.processQueue";

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder

@synthesize inputURL;
@synthesize outputURL;
@synthesize param = param;
@synthesize startTime;
@synthesize endTime;

@synthesize verbose;
@synthesize lastProgress;

@synthesize sbChannels;

@synthesize timeStamp0, timeStamp1;

- (instancetype)initWithInput:(NSURL*) input output:(NSURL*) output
{
    if (self = [super init]) {
        inputURL = input;
        outputURL = output;
        
        if ([self validate]) {
            param = [NSMutableDictionary dictionary];
            sbChannels = [NSMutableArray array];
            startTime = kCMTimeInvalid;
            endTime = kCMTimeInvalid;
            
            return self;
        }
    }
    return nil;
}

+ (instancetype)transcoderWithInput:(NSURL*) input output:(NSURL*) output
{
    return [[self alloc] initWithInput:input output:output];
}

- (BOOL)isReadable
{
    NSFileManager* mgr = [NSFileManager defaultManager];
    NSString* path = [self.inputURL path];
    if (mgr && path) {
        BOOL read = [mgr isReadableFileAtPath:path];
        return read;
    }
    return NO;
}

- (BOOL)isWritable
{
    NSFileManager* mgr = [NSFileManager defaultManager];
    NSString* path = [self.outputURL path];
    if (mgr && path) {
        BOOL exist = [mgr fileExistsAtPath:path];
        BOOL delete = [mgr isDeletableFileAtPath:path];
        BOOL create = [mgr isWritableFileAtPath:[path stringByDeletingLastPathComponent]];
        if (exist && delete && create) {
            return YES;
        }
        if (!exist && create) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)validate
{
    // Check access rights
    BOOL accessRights = [self isReadable] && [self isWritable];
    if (!accessRights) return NO;
    
    // Check movie
    AVMutableMovie* mov = [AVMutableMovie movieWithURL:inputURL options:nil];
    if (!mov) return NO;
    
    // Check AV tracks
    NSArray<AVMovieTrack*>* vTrack = [mov tracksWithMediaType:AVMediaTypeVideo];
    NSArray<AVMovieTrack*>* aTrack = [mov tracksWithMediaType:AVMediaTypeAudio];
    NSArray<AVMovieTrack*>* mTrack = [mov tracksWithMediaType:AVMediaTypeMuxed];
    if (vTrack.count == 0 && aTrack.count == 0 && mTrack.count == 0) return NO;
    
    // Check Duration
    Float64 length = CMTimeGetSeconds(mov.duration);
    if (length == 0) return NO;
    
    self.inMovie = mov;
    return YES;
}

- (BOOL)prepareRW
{
    NSError *error = nil;
    AVAssetReader* assetReader = [[AVAssetReader alloc] initWithAsset:self.inMovie
                                                                error:&error];
    if (!assetReader) {
        NSLog(@"[METranscoder] ERROR: Failed to init AVAssetReader");
        if (error)
            self.finalError = error;
        return FALSE;
    }
    self.assetReader = assetReader;
    //
    error = nil;
    AVAssetWriter* assetWriter = [[AVAssetWriter alloc] initWithURL:self.outputURL
                                                           fileType:AVFileTypeQuickTimeMovie
                                                              error:&error];
    if (!assetWriter) {
        NSLog(@"[METranscoder] ERROR: Failed to init AVAssetWriter");
        if (error)
            self.finalError = error;
        return FALSE;
    }
    self.assetWriter = assetWriter;
    return TRUE;
}

- (dispatch_queue_t) controlQueue
{
    if (!_controlQueue) {
        controlQueueKey = &controlQueueKey;
        void *unused = (__bridge void*)self;
        _controlQueue = dispatch_queue_create(kControlQueueLabel, DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_controlQueue, controlQueueKey, unused, NULL);
    }
    return _controlQueue;
}

- (dispatch_queue_t) processQueue
{
    if (!_processQueue) {
        processQueueKey = &processQueueKey;
        void *unused = (__bridge void*)self;
        _processQueue = dispatch_queue_create(kProcessQueueLabel, DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_processQueue, processQueueKey, unused, NULL);
    }
    return _processQueue;
}

- (void) registerMEManager:(MEManager *)meManager for:(CMPersistentTrackID)trackID
{
    NSMutableDictionary* mgrs = self.managers;
    if (mgrs == nil) {
        mgrs = [NSMutableDictionary dictionary];
        self.managers = mgrs;
    }
    if (mgrs) {
        NSString* key = keyForTrackID(trackID);
        mgrs[key] = meManager;
    }
}

- (void) registerMEAudioConverter:(MEAudioConverter *)meAudioConverter for:(CMPersistentTrackID)trackID
{
    NSMutableDictionary* mgrs = self.managers;
    if (mgrs == nil) {
        mgrs = [NSMutableDictionary dictionary];
        self.managers = mgrs;
    }
    if (mgrs) {
        NSString* key = keyForTrackID(trackID);
        mgrs[key] = meAudioConverter;
    }
}

- (void) startAsync
{
    // process export in background queue
    dispatch_queue_t queue = self.controlQueue;
    __weak typeof(self) wself = self;
    dispatch_async(queue, ^{
        [wself exportCustomOnError:nil]; // blocking method call
    });
}

- (void) cancelAsync
{
    @synchronized (self) {
        if (self.cancelled) return;
        [self cancelExportCustom];
    }
}

- (CFAbsoluteTime) timeElapsed
{
    CFAbsoluteTime ts0 = self.timeStamp0;
    CFAbsoluteTime ts1 = self.timeStamp1;
    if (ts0 && ts1) return (ts1 - ts0);
    if (ts0 > 0 && ts1 == 0) return (CFAbsoluteTimeGetCurrent() - ts0);
    return 0;
}

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder (export)

- (BOOL) post:(NSString*)description
       reason:(NSString*)failureReason
         code:(NSInteger)result
           to:(NSError**)error
{
    if (error) {
        if (!description) description = @"unknown description";
        if (!failureReason) failureReason = @"unknown failureReason";
        
        NSString *domain = @"com.MyCometG3.movencoder2.ErrorDomain";
        NSInteger code = (NSInteger)result;
        NSDictionary *userInfo = @{NSLocalizedDescriptionKey : description,
                                   NSLocalizedFailureReasonErrorKey : failureReason,};
        *error = [NSError errorWithDomain:domain code:code userInfo:userInfo];
        return YES;
    }
    return NO;
}

- (BOOL) exportCustomOnError:(NSError **)error
{
    self.timeStamp0 = CFAbsoluteTimeGetCurrent();
    self.timeStamp1 = 0;
    
    //
    AVMutableMovie* mov = self.inMovie;
    AVAssetWriter* aw = nil;
    AVAssetReader* ar = nil;
    BOOL useME = [self hasVideoMEManagers];  // for video processing
    BOOL useAC = [self hasAudioMEConverters]; // for audio converter processing
    
    dispatch_group_t dg;
    
    //
    if (self.writerIsBusy) {
        NSError* err = nil;
        [self post:[NSString stringWithFormat:@"%s (%d)", __PRETTY_FUNCTION__, __LINE__]
            reason:@"Multiple call is not allowed."
              code:paramErr
                to:&err];
        self.finalError = err;
        goto end;
    }
    
    //
    {
        NSFileManager *fm = [NSFileManager new];
        if ([fm fileExistsAtPath:[outputURL path]]) {
            if (![fm removeItemAtURL:outputURL error:nil]) {
                NSError* err = nil;
                [self post:[NSString stringWithFormat:@"%s (%d)", __PRETTY_FUNCTION__, __LINE__]
                    reason:@"Output file path is not writable."
                      code:paramErr
                        to:&err];
                self.finalError = err;
                goto end;
            }
        }
    }
    
    //
    if (!( CMTIME_IS_VALID(self.startTime)&&CMTIME_IS_VALID(self.endTime) )) {
        self.startTime = kCMTimeZero;
        self.endTime = mov.duration;
    } else {
        int compResult = CMTimeCompare(self.startTime, self.endTime);
        if (compResult >= 0) {
            self.startTime = kCMTimeZero;
            self.endTime = mov.duration;
        }
    }
    CMTimeRange maxRange = CMTimeRangeMake(self.startTime, self.endTime);
    self.startTime = CMTimeClampToRange(self.startTime, maxRange);
    self.endTime = CMTimeClampToRange(self.endTime, maxRange);
    self.writerIsBusy = TRUE;
    
    //
    if ( ![self prepareRW] ) {
        NSError* err = nil;
        [self post:[NSString stringWithFormat:@"%s (%d)", __PRETTY_FUNCTION__, __LINE__]
            reason:@"Either AVAssetReader or AVAssetWriter is not available."
              code:paramErr
                to:&err];
        self.finalError = err;
        goto end;
    }
    
    NSLog(@"[METranscoder] Export session started.");
    
    aw = self.assetWriter;
    ar = self.assetReader;
    
    {
        // setup AVAssetWriter parameters
        aw.movieTimeScale = mov.timescale;
        aw.movieFragmentInterval = kCMTimeInvalid;
        aw.shouldOptimizeForNetworkUse = TRUE;
        
        // setup sampleBufferChannels for each track
        if (useAC) {
            [self prepareAudioMEChannelsWith:mov from:ar to:aw];
        } else {
            [self prepareAudioMediaChannelWith:mov from:ar to:aw];
        }
        [self prepareOtherMediaChannelsWith:mov from:ar to:aw];
        if (useME) {
            [self prepareVideoMEChannelsWith:mov from:ar to:aw];
        } else {
            [self prepareVideoChannelsWith:mov from:ar to:aw];
        }
        
        // start assetReader/assetWriter
        BOOL arStarted = [ar startReading];
        BOOL awStarted = [aw startWriting];
        if (!(arStarted && awStarted)) {
            NSError* err = (!arStarted ? ar.error : aw.error);
            [ar cancelReading];
            [aw cancelWriting];
            self.finalSuccess = FALSE;
            self.finalError = err;
            [self rwDidFinished];
            goto end;
        }
        
        // start writing session
        [aw startSessionAtSourceTime:startTime];
    }
    
    // started callback
    [self rwDidStarted];
    
    // Register and run each sample buffer channels as dispatchgroup
    {
        dg = dispatch_group_create();
        NSArray<SBChannel*>* channelArray = self.sbChannels;
        for (SBChannel* sbc in channelArray) {
            dispatch_group_enter(dg);
            dispatch_block_t handler = ^{ dispatch_group_leave(dg); };
            [sbc startWithDelegate:self completionHandler:handler];
        }
    }
    
    // wait till finish
    {
        __weak typeof(self) wself = self;
        __weak typeof(AVAssetReader*) war = ar;
        __weak typeof(AVAssetWriter*) waw = aw;
        __block BOOL finish = FALSE;
        dispatch_semaphore_t waitSem = dispatch_semaphore_create(0);
        dispatch_group_notify(dg, self.processQueue, ^{
            BOOL finalize = TRUE;
            BOOL cancelled = wself.cancelled; // cancel request
            if (cancelled == FALSE) {
                // check reader status
                BOOL arFailed = (war.status == AVAssetReaderStatusFailed);
                if (arFailed) {
                    wself.finalSuccess = FALSE;
                    wself.finalError = war.error;
                    finalize = FALSE;
                }
            }
            if (finalize) {
                // finish writing session
                [waw endSessionAtSourceTime:wself.endTime];
                
                dispatch_semaphore_t finishSem = dispatch_semaphore_create(0);
                [waw finishWritingWithCompletionHandler:^{
                    BOOL awFailed = (waw.status == AVAssetWriterStatusFailed);
                    if (awFailed) {
                        wself.finalSuccess = FALSE;
                        wself.finalError = war.error;
                    } else {
                        finish = !cancelled;
                    }
                    dispatch_semaphore_signal(finishSem);
                }];
                dispatch_semaphore_wait(finishSem, DISPATCH_TIME_FOREVER);
            }
            
            [war cancelReading];
            [waw cancelWriting];
            [wself rwDidFinished];
            dispatch_semaphore_signal(waitSem);
        });
        dispatch_semaphore_wait(waitSem, DISPATCH_TIME_FOREVER);
        
        if (finish) {
            wself.finalSuccess = TRUE;
            wself.finalError = nil;
        }
    }
    
end:
    self.writerIsBusy = FALSE;
    if (self.finalSuccess) {
        NSLog(@"[METranscoder] Export session completed.");
    } else if (self.cancelled) {
        NSLog(@"[METranscoder] Export session cancelled.");
    } else {
        if (!self.finalError) {
            NSError* err = nil;
            [self post:[NSString stringWithFormat:@"%s (%d)", __PRETTY_FUNCTION__, __LINE__]
                reason:@"Unexpected internal failure."
                  code:paramErr
                    to:&err];
            self.finalError = err;
        }
        if (error) {
            *error = self.finalError;
        }
        NSLog(@"[METranscoder] ERROR: Export session failed. \n%@", self.finalError);
    }
    
    //
    self.timeStamp1 = CFAbsoluteTimeGetCurrent();
    NSLog(@"[METranscoder] elapsed: %.2f sec", self.timeElapsed);

    return self.finalSuccess;
}

- (void) cancelExportCustom
{
    __weak typeof(self) wself = self;
    dispatch_async(self.processQueue, ^{
        NSMutableArray<SBChannel*>* channels = wself.sbChannels;
        for (SBChannel* sbc in channels) {
            [sbc cancel];
        }
        self.cancelled = TRUE;
    });
}

// MARK: # callback handler

/**
 Enqueue startCallback
 */
- (void) rwDidStarted
{
    dispatch_queue_t queue = self.callbackQueue;
    dispatch_block_t block = self.startCallback;
    if (queue && block) {
        dispatch_async(queue, block);
    }
}

/**
 Enqueue completionCallback
 */
- (void) rwDidFinished
{
    dispatch_queue_t queue = self.callbackQueue;
    dispatch_block_t block = self.completionCallback;
    if (queue && block) {
        dispatch_async(queue, block);
    }
}

static float calcProgressOf(CMSampleBufferRef buffer, CMTime startTime, CMTime endTime) {
    
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(buffer);
    CMTime dur = CMSampleBufferGetDuration(buffer);
    if (CMTIME_IS_NUMERIC(dur))
        pts = CMTimeAdd(pts, dur);
    Float64 offsetSec = CMTimeGetSeconds(CMTimeSubtract(pts, startTime));
    Float64 lenSec = CMTimeGetSeconds(CMTimeSubtract(endTime, startTime));
    Float64 progress = (lenSec > 0.0) ? (offsetSec/lenSec) : 0.0;
    return progress * 100.0;
}

/**
 Enqueue progressCallback <SBChannelDelegate>

 @param sb CMSampleBuffer
 @param channel SBChannel (one for normal track, two for ME Channel)
 */
- (void) didReadBuffer:(CMSampleBufferRef)sb from:(SBChannel*)channel
{
    dispatch_queue_t queue = self.callbackQueue;
    progress_block_t block = self.progressCallback;
    if (queue && block) {
        float progress = calcProgressOf(sb, self.startTime, self.endTime);
        float pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb));
        float dts = CMTimeGetSeconds(CMSampleBufferGetDecodeTimeStamp(sb));
        int count = channel.count;
        
        NSMutableDictionary* info = [channel.info mutableCopy];
        info[kProgressPercentKey] = @(progress);
        info[kProgressPTSKey] = @(pts);
        info[kProgressDTSKey] = @(dts);
        info[kProgressCountKey] = @(count);
        dispatch_async(queue, ^{
            block(info);
        });
    }
}

- (BOOL) hasVideoMEManagers
{
    if (!self.managers) return NO;
    
    for (NSString* key in self.managers) {
        id manager = self.managers[key];
        if ([manager isKindOfClass:[MEManager class]]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL) hasAudioMEConverters
{
    if (!self.managers) return NO;
    
    for (NSString* key in self.managers) {
        id manager = self.managers[key];
        if ([manager isKindOfClass:[MEAudioConverter class]]) {
            return YES;
        }
    }
    return NO;
}

@end

NS_ASSUME_NONNULL_END
