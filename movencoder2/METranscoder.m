//
//  METranscoder.m
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

// MARK: # prepareChannels

- (void) prepareCopyChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw of:(AVMediaType)type;
- (void) prepareOtherMediaChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;
- (void) prepareAudioMediaChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;
- (void) prepareAudioMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

- (BOOL) hasFieldModeSupportOf:(AVMovieTrack*)track;
- (void) addDecommpressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting;
- (NSMutableDictionary<NSString*,id>*) videoCompressionSettingFor:(AVMovieTrack *)track;

- (void) prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;
- (void) prepareVideoMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

- (BOOL) hasVideoMEManagers;
- (BOOL) hasAudioMEConverters;

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

@property (nonatomic, readonly) BOOL videoEncode;
@property (nonatomic, readonly) NSString* videoFourcc;
@property (nonatomic, readonly) int videoBitRate;
@property (nonatomic, readonly) BOOL copyField;
@property (nonatomic, readonly) BOOL copyNCLC;

@property (nonatomic, readonly) uint32_t audioFormatID;
@property (nonatomic, readonly) uint32_t videoFormatID;
@property (nonatomic, readonly) uint32_t audioChannelLayoutTag;

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder

@synthesize inputURL;
@synthesize outputURL;
@synthesize param;
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

static inline NSString* keyForTrackID(CMPersistentTrackID trackID) {
    NSString* key = [NSString stringWithFormat:@"trackID:%d", trackID];
    return key;
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

// MARK: # prepareChannels

- (void) prepareCopyChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw of:(AVMediaType)type
{
    for (AVAssetTrack* track in [movie tracksWithMediaType:type]) {
        // source
        NSDictionary<NSString*,id>* arOutputSetting = nil;
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:arOutputSetting];
        
        // destination
        NSDictionary<NSString*,id>* awInputSetting = nil;
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:type outputSettings:awInputSetting];
        if (type != AVMediaTypeAudio) {
            awInput.mediaTimeScale = track.naturalTimeScale;
        }
        
        BOOL arOK = [ar canAddOutput:arOutput];
        BOOL awOK = [aw canAddInput:awInput];
        
        if (!(arOK && awOK)) {
            NSLog(@"[METranscoder] Skipping track(%d) - unsupported", track.trackID);
            continue;
        }
        
        [ar addOutput:arOutput];
        [aw addInput:awInput];
        
        // channel
        SBChannel* sbcCopy = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                     consumerME:(MEInput*)awInput
                                                        TrackID:track.trackID];
        [sbChannels addObject:sbcCopy];
    }
}

- (void) prepareOtherMediaChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (!self.copyOtherMedia) return;
    
    // copy non-av media type (excludes muxed media)
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeText];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeClosedCaption];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeSubtitle];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeTimecode];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeMetadata];
    [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeDepthData];
}

- (void) prepareAudioMediaChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (self.audioEncode == FALSE) {
        [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeAudio];
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeAudio]) {
        // source
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        arOutputSetting[AVFormatIDKey] = @(kAudioFormatLinearPCM);
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        [ar addOutput:arOutput];
        
        // preserve original sampleRate, numChannel, and audioChannelLayout(best effort)
        int sampleRate = 0;
        int numChannel = 0;
        AVAudioChannelLayout* avacSrcLayout = nil;
        AVAudioChannelLayout* avacDstLayout = nil;
        NSData* aclData = nil;
        
        NSArray* descArray = track.formatDescriptions;
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef) descArray[0];
        
        const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc);
        assert(asbd != NULL);
        sampleRate = (int)asbd->mSampleRate;
        numChannel = (int)asbd->mChannelsPerFrame;
        
        size_t srcAclSize = 0;
        const AudioChannelLayout* srcAclPtr = CMAudioFormatDescriptionGetChannelLayout(desc, &srcAclSize);
        if (srcAclPtr != NULL && srcAclSize > 0) {
            // Validate AudioChannelLayout
            AudioChannelLayoutTag srcTag = srcAclPtr->mChannelLayoutTag;
            AudioChannelLayoutTag dstTag = 0;
            if (self.audioChannelLayoutTag != 0) {
                dstTag = self.audioChannelLayoutTag;
            } else {
                UInt32 ioPropertyDataSize = 4;
                UInt32 outPropertyData = 0;
                OSStatus err = AudioFormatGetProperty(kAudioFormatProperty_NumberOfChannelsForLayout,
                                                      (UInt32)srcAclSize,
                                                      srcAclPtr,
                                                      &ioPropertyDataSize,
                                                      &outPropertyData);
                assert (!err && outPropertyData > 0);
                numChannel = (int)outPropertyData;
                
                if (AudioChannelLayoutTag_GetNumberOfChannels(srcTag)) {
                    // Request to respect LayoutTag for destination
                    dstTag = srcTag;
                } else {
                    // set of AudioChannelLabel(s), based on kAudioChannelLayoutTag_MPEG_*
                    NSSet* setCh1    = [NSSet setWithObjects:@(3), nil]; // C
                    NSSet* setCh2    = [NSSet setWithObjects:@(1),@(2), nil]; // L R
                    NSSet* setCh3    = [NSSet setWithObjects:@(1),@(2),@(3), nil]; // L R C
                    NSSet* setCh4    = [NSSet setWithObjects:@(1),@(2),@(3),@(9), nil]; // L R C Cs
                    NSSet* setCh5    = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6), nil]; // L R C Ls Rs
                    NSSet* setCh51   = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6), nil]; // L R C LFE Ls Rs
                    NSSet* setCh61   = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(9), nil]; // L R C LFE Ls Rs Cs
                    NSSet* setCh71AB = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(7),@(8), nil]; // L R C LFE Ls Rs Lc Rc
                    NSSet* setCh71C  = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(33),@(34), nil]; // L R C LFE Ls Rs Rls Rrs
                    
                    // set of AudioChannelLabel(s), based on kAudioChannelLayoutTag_AAC_*
                    NSSet* setAACQ   = [NSSet setWithObjects:@(1),@(2),@(5),@(6), nil]; // L R Ls Rs
                    NSSet* setAAC60  = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6),@(9), nil]; // L R C Ls Rs Cs
                    NSSet* setAAC70  = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6),@(33),@(34), nil]; // L R C Ls Rs Rls Rrs
                    NSSet* setAAC71C = [NSSet setWithObjects:@(1),@(2),@(3),@(4),@(5),@(6),@(13),@(15), nil]; // L R C LFE Ls Rs Vhl Vhr
                    NSSet* setAACOct = [NSSet setWithObjects:@(1),@(2),@(3),@(5),@(6),@(9),@(33),@(34), nil]; // L R C Ls Rs Cs Rls Rrs
                    
                    if (srcTag == kAudioChannelLayoutTag_UseChannelBitmap) {
                        // prepare dictionaries for translation
                        NSDictionary<NSString*,NSNumber*>* bitmaps = @{
                            @"Left"                 : @(1U<<0 ), // L
                            @"Right"                : @(1U<<1 ), // R
                            @"Center"               : @(1U<<2 ), // C
                            @"LFEScreen"            : @(1U<<3 ), // LFE
                            @"LeftSurround"         : @(1U<<4 ), // Ls
                            @"RightSurround"        : @(1U<<5 ), // Rs
                            @"LeftCenter"           : @(1U<<6 ), // Lc
                            @"RightCenter"          : @(1U<<7 ), // Rc
                            @"CenterSurround"       : @(1U<<8 ), // Cs
                            @"LeftSurroundDirect"   : @(1U<<9 ), // Lsd
                            @"RightSurroundDirect"  : @(1U<<10), // Rsd
                            @"TopCenterSurround"    : @(1U<<11), // Ts
                            @"VerticalHeightLeft"   : @(1U<<12), // Vhl
                            @"VerticalHeightCenter" : @(1U<<13), // Vhc
                            @"VerticalHeightRight"  : @(1U<<14), // Vhr
                            @"TopBackLeft"          : @(1U<<15), //
                            @"TopBackCenter"        : @(1U<<16), //
                            @"TopBackRight"         : @(1U<<17), //
                        //  @"LeftTopFront"         : @(1U<<12), //
                        //  @"CenterTopFront"       : @(1U<<13), //
                        //  @"RightTopFront"        : @(1U<<14), //
                            @"LeftTopMiddle"        : @(1U<<21), // Ltm
                        //  @"CenterTopMiddle"      : @(1U<<11), //
                            @"RightTopMiddle"       : @(1U<<23), // Rtm
                            @"LeftTopRear"          : @(1U<<24), // Ltr
                            @"CenterTopRear"        : @(1U<<25), // Ctr
                            @"RightTopRear"         : @(1U<<26), // Rtr
                        };
                        NSDictionary<NSString*,NSNumber*>* labelsForBitmap = @{
                            @"Left"                 : @(1 ), // L
                            @"Right"                : @(2 ), // R
                            @"Center"               : @(3 ), // C
                            @"LFEScreen"            : @(4 ), // LFE
                            @"LeftSurround"         : @(5 ), // Ls
                            @"RightSurround"        : @(6 ), // Rs
                            @"LeftCenter"           : @(7 ), // Lc
                            @"RightCenter"          : @(8 ), // Rc
                            @"CenterSurround"       : @(9 ), // Cs
                            @"LeftSurroundDirect"   : @(10), // Lsd
                            @"RightSurroundDirect"  : @(11), // Rsd
                            @"TopCenterSurround"    : @(12), // Ts
                            @"VerticalHeightLeft"   : @(13), // Vhl
                            @"VerticalHeightCenter" : @(14), // Vhc
                            @"VerticalHeightRight"  : @(15), // Vhr
                            @"TopBackLeft"          : @(16), //
                            @"TopBackCenter"        : @(17), //
                            @"TopBackRight"         : @(18), //
                        //  @"LeftTopFront"         : @(13), //
                        //  @"CenterTopFront"       : @(14), //
                        //  @"RightTopFront"        : @(15), //
                            @"LeftTopMiddle"        : @(49), // Ltm
                        //  @"CenterTopMiddle"      : @(12), //
                            @"RightTopMiddle"       : @(51), // Rtm
                            @"LeftTopRear"          : @(52), // Ltr
                            @"CenterTopRear"        : @(53), // Ctr
                            @"RightTopRear"         : @(54), // Rtr
                        };
                        
                        // parse AudioChannelBitmap(s)
                        NSMutableSet* srcSet = [NSMutableSet new];
                        
                        AudioChannelBitmap map = srcAclPtr->mChannelBitmap;
                        for (NSString* name in bitmaps.allKeys) {
                            NSNumber* numBitmap = bitmaps[name];
                            if (numBitmap != nil) {
                                UInt32 testBit = numBitmap.unsignedIntValue;
                                if (map & testBit) {
                                    NSNumber* numLabel = labelsForBitmap[name];
                                    if (numLabel != nil) {
                                        [srcSet addObject: numLabel];
                                    }
                                }
                            }
                        }
                        
                        // Update numChannel w/ valid channel count
                        assert(srcSet.count); // No support for Lsd, Rsd, Rls, Rrs and any Top positions
                        numChannel = (int)srcSet.count;
                        
                        // get destination tag for AAC Transcode
                        if ([srcSet isEqualToSet:setCh1]) {
                            dstTag = kAudioChannelLayoutTag_Mono;       // kAudioChannelLayoutTag_MPEG_1_0
                        }
                        else if ([srcSet isEqualToSet:setCh2]) {
                            dstTag = kAudioChannelLayoutTag_Stereo;     // kAudioChannelLayoutTag_MPEG_2_0
                        }
                        else if ([srcSet isEqualToSet:setCh3]) {
                            dstTag = kAudioChannelLayoutTag_AAC_3_0;    // kAudioChannelLayoutTag_MPEG_3_0_B, 3_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh4]) {
                            dstTag = kAudioChannelLayoutTag_AAC_4_0;    // kAudioChannelLayoutTag_MPEG_4_0_B, 4_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh5]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_0;    // kAudioChannelLayoutTag_MPEG_5_0_D, 5_0_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh51]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_1;    // kAudioChannelLayoutTag_MPEG_5_1_D, 5_1_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh61]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_1;    // kAudioChannelLayoutTag_MPEG_6_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71AB]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1;    // kAudioChannelLayoutTag_MPEG_7_1_B, 7_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71C]) {
                            // No equivalent available: AudioChannelBitmap does not offer Rls/Rrs layout support.
                        }
                        else if ([srcSet isEqualToSet:setAACQ]) {
                            dstTag = kAudioChannelLayoutTag_AAC_Quadraphonic;
                        }
                        else if ([srcSet isEqualToSet:setAAC60]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_0;
                        }
                        else if ([srcSet isEqualToSet:setAAC70]) {
                            // No equivalent available: AudioChannelBitmap does not offer Rls/Rrs layout support.
                        }
                        else if ([srcSet isEqualToSet:setAAC71C]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1_C;
                        }
                        else if ([srcSet isEqualToSet:setAACOct]) {
                            // No equivalent available: AudioChannelBitmap does not offer Rls/Rrs layout support.
                        }
                        assert(dstTag);
                    }
                    
                    if (srcTag == kAudioChannelLayoutTag_UseChannelDescriptions) {
                        // parse AudioChannelDescription(s)
                        NSMutableSet* srcSet = [NSMutableSet new];
                        
                        UInt32 srcDescCount = srcAclPtr->mNumberChannelDescriptions;
                        size_t offset = offsetof(struct AudioChannelLayout, mChannelDescriptions);
                        AudioChannelDescription* descPtr = (AudioChannelDescription*)((char*)srcAclPtr + offset);
                        for (size_t desc = 0; desc < srcDescCount; desc++) {
                            AudioChannelLabel label = descPtr[desc].mChannelLabel;
                            if (label != kAudioChannelLabel_Unused && label != kAudioChannelLabel_UseCoordinates) {
                                [srcSet addObject: @(label)];
                            }
                        }
                        
                        // Update numChannel w/ valid channel count
                        assert(srcSet.count); // kAudioChannelLabel_UseCoordinates is not supported
                        numChannel = (int)srcSet.count;
                        
                        // get destination tag for AAC Transcode
                        if ([srcSet isEqualToSet:setCh1]) {
                            dstTag = kAudioChannelLayoutTag_Mono;       // kAudioChannelLayoutTag_MPEG_1_0
                        }
                        else if ([srcSet isEqualToSet:setCh2]) {
                            dstTag = kAudioChannelLayoutTag_Stereo;     // kAudioChannelLayoutTag_MPEG_2_0
                        }
                        else if ([srcSet isEqualToSet:setCh3]) {
                            dstTag = kAudioChannelLayoutTag_AAC_3_0;    // kAudioChannelLayoutTag_MPEG_3_0_B, 3_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh4]) {
                            dstTag = kAudioChannelLayoutTag_AAC_4_0;    // kAudioChannelLayoutTag_MPEG_4_0_B, 4_0_A
                        }
                        else if ([srcSet isEqualToSet:setCh5]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_0;    // kAudioChannelLayoutTag_MPEG_5_0_D, 5_0_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh51]) {
                            dstTag = kAudioChannelLayoutTag_AAC_5_1;    // kAudioChannelLayoutTag_MPEG_5_1_D, 5_1_C/B/A
                        }
                        else if ([srcSet isEqualToSet:setCh61]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_1;    // kAudioChannelLayoutTag_MPEG_6_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71AB]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1;    // kAudioChannelLayoutTag_MPEG_7_1_B, 7_1_A
                        }
                        else if ([srcSet isEqualToSet:setCh71C]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1_B;  // kAudioChannelLayoutTag_MPEG_7_1_C
                        }
                        else if ([srcSet isEqualToSet:setAACQ]) {
                            dstTag = kAudioChannelLayoutTag_AAC_Quadraphonic;
                        }
                        else if ([srcSet isEqualToSet:setAAC60]) {
                            dstTag = kAudioChannelLayoutTag_AAC_6_0;
                        }
                        else if ([srcSet isEqualToSet:setAAC70]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_0;
                        }
                        else if ([srcSet isEqualToSet:setAAC71C]) {
                            dstTag = kAudioChannelLayoutTag_AAC_7_1_C;
                        }
                        else if ([srcSet isEqualToSet:setAACOct]) {
                            dstTag = kAudioChannelLayoutTag_AAC_Octagonal;
                        }
                        assert(dstTag);
                    }
                }
            }
            
            // For Source, use AudioChannelLayout* inside CMAudioFormatDescription
            avacSrcLayout = [AVAudioChannelLayout layoutWithLayout:srcAclPtr];
            // For Destination, use AudioChannelLayoutTag_AAC_*
            avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
        } else {
            // If acl is not available, use dummy layout (best effort)
            assert(0 < numChannel && numChannel <=8);
            
            // For Source (suppose MPEG layout)
            AudioChannelLayoutTag srcTag = kMEMPEGSourceLayouts[numChannel - 1];
            avacSrcLayout = [AVAudioChannelLayout layoutWithLayoutTag:srcTag];
            
            // For Destination (suppose AAC layout)
            AudioChannelLayoutTag dstTag = kMEAACDestinationLayouts[numChannel - 1];
            avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
        }
        
        // Prepare NSData* of destination layout
        UInt32 acDescCount = avacDstLayout.layout->mNumberChannelDescriptions;
        size_t acDescSize = sizeof(AudioChannelDescription);
        size_t acLayoutSize = sizeof(AudioChannelLayout) + MIN(acDescCount - 1, 0) * acDescSize;
        aclData = [NSData dataWithBytes:avacDstLayout.layout length:acLayoutSize];
        
        // destination
        NSMutableDictionary<NSString*,id>* awInputSetting = [NSMutableDictionary dictionary];
        awInputSetting[AVFormatIDKey] = @(self.audioFormatID);
        awInputSetting[AVSampleRateKey] = @(sampleRate);
        awInputSetting[AVNumberOfChannelsKey] = @(numChannel);
        awInputSetting[AVChannelLayoutKey] = aclData;
        awInputSetting[AVSampleRateConverterAlgorithmKey] = AVSampleRateConverterAlgorithm_Normal;
        //awInputSetting[AVSampleRateConverterAudioQualityKey] = AVAudioQualityMedium;
        
        if ([self.audioFourcc isEqualToString:@"lpcm"]) {
            awInputSetting[AVLinearPCMIsBigEndianKey] = false;
            awInputSetting[AVLinearPCMIsFloatKey] = false;
            awInputSetting[AVLinearPCMBitDepthKey] = @(self.lpcmDepth);
            awInputSetting[AVLinearPCMIsNonInterleavedKey] = false;
        } else {
            awInputSetting[AVEncoderBitRateKey] = @(self.audioBitRate);
            awInputSetting[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_LongTermAverage;
            //awInputSetting[AVEncoderAudioQualityKey] = AVAudioQualityMedium;
        }
        
        // validate bitrate
        if (awInputSetting[AVEncoderBitRateKey]) {
            AVAudioFormat* inFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(double)sampleRate
                                                                                channelLayout:avacSrcLayout];
            AVAudioFormat* outFormat = [[AVAudioFormat alloc] initWithSettings:awInputSetting];
            AVAudioConverter* converter = [[AVAudioConverter alloc] initFromFormat:inFormat toFormat:outFormat];
            NSArray<NSNumber*>* bitrateArray = converter.applicableEncodeBitRates;
            if ([bitrateArray containsObject:@(self.audioBitRate)] == false) {
                // bitrate adjustment
                NSNumber* prev = bitrateArray.firstObject;
                for (NSNumber* item in bitrateArray) {
                    if ([item compare:prev] == NSOrderedDescending) {
                        prev = item;
                    }
                }
                awInputSetting[AVEncoderBitRateKey] = prev;
                NSLog(@"[METranscoder] Bitrate adjustment to %@ from %@", prev, @(self.audioBitRate));
            }
        }
        
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                         outputSettings:awInputSetting];
        // awInput.mediaTimeScale = track.naturalTimeScale; // Audio track is unable to change
        [aw addInput:awInput];
        
        // channel
        SBChannel* sbcAudio = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                      consumerME:(MEInput*)awInput
                                                         TrackID:track.trackID];
        [sbChannels addObject:sbcAudio];
    }
}

- (void) prepareAudioMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (self.audioEncode == FALSE) {
        [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeAudio];
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeAudio]) {
        // Check if we have a registered MEAudioConverter for this track
        NSString* key = keyForTrackID(track.trackID);
        MEAudioConverter* audioConverter = self.managers[key];
        if (![audioConverter isKindOfClass:[MEAudioConverter class]]) {
            // Fall back to regular audio processing if no MEAudioConverter registered
            [self prepareAudioMediaChannelWith:movie from:ar to:aw];
            return;
        }
        
        // Get source audio parameters
        NSArray* descArray = track.formatDescriptions;
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef) descArray[0];
        const AudioStreamBasicDescription* asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc);
        if (!asbd) {
            NSLog(@"[METranscoder] Skipping audio track(%d) - no audio format description", track.trackID);
            continue;
        }
        
        int sampleRate = (int)asbd->mSampleRate;
        int numChannel = (int)asbd->mChannelsPerFrame;
        
        /* ========================================================================================== */
        
        // Get source AudioChannelLayout and determine target layout
        AVAudioChannelLayout* avacSrcLayout = nil;
        AVAudioChannelLayout* avacDstLayout = nil;
        
        size_t srcAclSize = 0;
        const AudioChannelLayout* srcAclPtr = CMAudioFormatDescriptionGetChannelLayout(desc, &srcAclSize);
        if (srcAclPtr != NULL && srcAclSize > 0) {
            // Use existing layout parsing logic from the original method
            AudioChannelLayoutTag srcTag = srcAclPtr->mChannelLayoutTag;
            AudioChannelLayoutTag dstTag = 0;
            
            if (self.audioChannelLayoutTag != 0) {
                dstTag = self.audioChannelLayoutTag;
            } else {
                // Channel layout analysis and mapping (basic implementation)
                UInt32 ioPropertyDataSize = 4;
                UInt32 outPropertyData = 0;
                OSStatus err = AudioFormatGetProperty(kAudioFormatProperty_NumberOfChannelsForLayout,
                                                      (UInt32)srcAclSize,
                                                      srcAclPtr,
                                                      &ioPropertyDataSize,
                                                      &outPropertyData);
                if (!err && outPropertyData > 0) {
                    numChannel = (int)outPropertyData;
                }
                
                if (AudioChannelLayoutTag_GetNumberOfChannels(srcTag)) {
                    dstTag = srcTag;
                } else {
                    // Fallback to channel count based mapping
                    if (numChannel >= 1 && numChannel <= 8) {
                        dstTag = kMEAACDestinationLayouts[numChannel - 1];
                    }
                }
            }
            
            avacSrcLayout = [AVAudioChannelLayout layoutWithLayout:srcAclPtr];
            if (dstTag != 0) {
                avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
            }
        } else {
            // Default layouts when source has no channel layout
            if (numChannel >= 1 && numChannel <= 8) {
                AudioChannelLayoutTag srcTag = kMEMPEGSourceLayouts[numChannel - 1];
                AudioChannelLayoutTag dstTag = kMEAACDestinationLayouts[numChannel - 1];
                avacSrcLayout = [AVAudioChannelLayout layoutWithLayoutTag:srcTag];
                avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:dstTag];
            } else {
                NSLog(@"[METranscoder] Skipping audio track(%d) - unsupported channel count %d", track.trackID, numChannel);
                continue;
            }
        }
        
        if (!avacSrcLayout || !avacDstLayout) {
            // Fallback: try to create layouts based on channel count only
            if (numChannel >= 1 && numChannel <= 8) {
                AudioChannelLayoutTag fallbackTag = kMEAACDestinationLayouts[numChannel - 1];
                if (!avacSrcLayout) {
                    avacSrcLayout = [AVAudioChannelLayout layoutWithLayoutTag:fallbackTag];
                }
                if (!avacDstLayout) {
                    avacDstLayout = [AVAudioChannelLayout layoutWithLayoutTag:fallbackTag];
                }
            }
        }
        
        if (!avacSrcLayout || !avacDstLayout) {
            NSLog(@"[METranscoder] Skipping audio track(%d) - channel layout creation failed", track.trackID);
            continue;
        }
        
        /* ========================================================================================== */
        
        // Prepare destination AudioChannelLayout data with proper size calculation
        UInt32 acDescCount = avacDstLayout.layout->mNumberChannelDescriptions;
        size_t acDescSize = sizeof(AudioChannelDescription);
        size_t acLayoutSize = sizeof(AudioChannelLayout) + (acDescCount > 1 ? (acDescCount - 1) * acDescSize : 0);
        NSData* aclData = [NSData dataWithBytes:avacDstLayout.layout length:acLayoutSize];
        
        // Destination format settings
        NSMutableDictionary<NSString*,id>* awInputSetting = [NSMutableDictionary dictionary];
        awInputSetting[AVFormatIDKey] = @(self.audioFormatID);
        awInputSetting[AVSampleRateKey] = @(sampleRate);
        awInputSetting[AVNumberOfChannelsKey] = @(avacDstLayout.channelCount);
        awInputSetting[AVChannelLayoutKey] = aclData;
        awInputSetting[AVSampleRateConverterAlgorithmKey] = AVSampleRateConverterAlgorithm_Normal;
        
        if ([self.audioFourcc isEqualToString:@"lpcm"]) {
            //
            awInputSetting[AVLinearPCMIsBigEndianKey] = @NO;
            awInputSetting[AVLinearPCMIsFloatKey] = @NO;
            awInputSetting[AVLinearPCMBitDepthKey] = @(self.lpcmDepth);
            awInputSetting[AVLinearPCMIsNonInterleavedKey] = @NO;
        } else {
            awInputSetting[AVEncoderBitRateKey] = @(self.audioBitRate);
            awInputSetting[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_LongTermAverage;
        }
        
        // Source configuration - force Float32 deinterleaved PCM
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        arOutputSetting[AVFormatIDKey] = @(kAudioFormatLinearPCM);
        arOutputSetting[AVLinearPCMIsFloatKey] = @YES;
        arOutputSetting[AVLinearPCMBitDepthKey] = @32;
        arOutputSetting[AVLinearPCMIsNonInterleavedKey] = @YES; // deinterleaved
        arOutputSetting[AVLinearPCMIsBigEndianKey] = @NO;
        
        /* ========================================================================================== */
        
        // NOTE: Audio format transition (2 layouts, 3 formats)
        //   arOutput
        //     (srcACL, Float32 deinterleaved); srcFormat
        //   MEAudioConverter
        //     (dstACL, Float32 deinterleaved); intermediateFormat
        //   awInput
        //     (dstACL, encoded); dstFormat
        
        // Source audio format with source layout - Force Float32 deinterleaved PCM
        AVAudioFormat* srcFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(double)sampleRate
                                                                             channelLayout:avacSrcLayout];
        
        // Intermediate audio format with destination layout - Force Float32 deinterleaved PCM
        AVAudioFormat* intermediateFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(double)sampleRate
                                                                                      channelLayout:avacDstLayout];
        
        // Destination audio format with destination layout - using transcode settings
        AVAudioFormat* dstFormat = [[AVAudioFormat alloc] initWithSettings:awInputSetting];
        
        if (!srcFormat || !intermediateFormat || !dstFormat) {
            NSLog(@"[METranscoder] Skipping audio track(%d) - unsupported audio format detected", track.trackID);
            continue;
        }
        
        // Validate and adjust bitrate using AVAudioConverter
        if (awInputSetting[AVEncoderBitRateKey]) {
            AVAudioConverter* converter = [[AVAudioConverter alloc] initFromFormat:intermediateFormat
                                                                          toFormat:dstFormat];
            if (converter) {
                NSArray<NSNumber*>* bitrateArray = converter.applicableEncodeBitRates;
                if (bitrateArray && ![bitrateArray containsObject:@(self.audioBitRate)]) {
                    // Find the closest supported bitrate
                    NSNumber* closestBitrate = bitrateArray.firstObject;
                    NSInteger targetBitrate = self.audioBitRate;
                    NSInteger minDiff = ABS(closestBitrate.integerValue - targetBitrate);
                    
                    for (NSNumber* bitrate in bitrateArray) {
                        NSInteger diff = ABS(bitrate.integerValue - targetBitrate);
                        if (diff < minDiff) {
                            minDiff = diff;
                            closestBitrate = bitrate;
                        }
                    }
                    
                    awInputSetting[AVEncoderBitRateKey] = closestBitrate;
                    NSLog(@"[METranscoder] Bitrate adjustment to %@ from %@", closestBitrate, @(self.audioBitRate));
                    
                    // Recreate destination format with adjusted bitrate
                    dstFormat = [[AVAudioFormat alloc] initWithSettings:awInputSetting];
                    if (!dstFormat) {
                        NSLog(@"[METranscoder] Skipping audio track(%d) - destination format recreation failed", track.trackID);
                        continue;
                    }
                }
            }
        }
        
        /* ========================================================================================== */
        
        // Configure the MEAudioConverter
        audioConverter.sourceFormat = srcFormat;
        audioConverter.destinationFormat = intermediateFormat;
        audioConverter.startTime = self.startTime;
        audioConverter.endTime = self.endTime;
        audioConverter.verbose = self.verbose;
        audioConverter.sourceExtensions = CMFormatDescriptionGetExtensions(desc);
        audioConverter.mediaTimeScale = track.naturalTimeScale;
        
        /* ========================================================================================== */
        
        // Create AVAssetReaderTrackOutput
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        if (![ar canAddOutput:arOutput]) {
            NSLog(@"[METranscoder] Skipping audio track(%d) - reader output not supported", track.trackID);
            continue;
        }
        [ar addOutput:arOutput];
        
        // Source channel: AVAssetReaderOutput -> MEAudioConverter (acting as MEInput)
        SBChannel* sbcMEInput = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                        consumerME:(MEInput*)audioConverter
                                                           TrackID:track.trackID];
        [sbChannels addObject:sbcMEInput];
        
        /* ========================================================================================== */
        
        // Create AVAssetWriterInput
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                         outputSettings:awInputSetting];
        if (![aw canAddInput:awInput]) {
            NSLog(@"[METranscoder] Skipping audio track(%d) - writer input not supported", track.trackID);
            continue;
        }
        [aw addInput:awInput];
        
        // Destination channel: MEAudioConverter (acting as MEOutput) -> AVAssetWriterInput
        SBChannel* sbcMEOutput = [SBChannel sbChannelWithProducerME:(MEOutput*)audioConverter
                                                         consumerME:(MEInput*)awInput
                                                            TrackID:track.trackID];
        [sbChannels addObject:sbcMEOutput];
    }
}

- (BOOL) hasFieldModeSupportOf:(AVMovieTrack*)track
{
    BOOL result = FALSE;
    NSArray* descArray = track.formatDescriptions;
    
    CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef) descArray[0];
    CFDictionaryRef dict = NULL;
    VTDecompressionSessionRef decompSession = NULL;
    {
        OSStatus status = noErr;
        CFDictionaryRef spec = NULL;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              desc,
                                              spec,
                                              NULL,
                                              NULL,
                                              &decompSession);
        if (status != noErr) return FALSE;
        
        status = VTSessionCopySupportedPropertyDictionary(decompSession, &dict);
        
        if (status != noErr) goto end;
    }
    
    if (dict) {
        CFDictionaryRef propFieldMode = CFDictionaryGetValue(dict, kVTDecompressionPropertyKey_FieldMode);
        if (propFieldMode) {
            CFArrayRef propList = CFDictionaryGetValue(propFieldMode, kVTPropertySupportedValueListKey);
            if (propList) {
                result = CFArrayContainsValue(propList,
                                              CFRangeMake(0, CFArrayGetCount(propList)),
                                              kVTDecompressionProperty_FieldMode_BothFields);
            }
        }
    }
    
end:
    if (decompSession) {
        VTDecompressionSessionInvalidate(decompSession);
        CFRelease(decompSession);
    }
    return result;
}

- (void) addDecommpressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting
{
    if ([self hasFieldModeSupportOf:track]) {
        NSDictionary* decompressionProperties = nil;
        
        // Keep both fields
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        dict[(__bridge NSString*)kVTDecompressionPropertyKey_FieldMode] = (__bridge NSString*)kVTDecompressionProperty_FieldMode_BothFields;
        decompressionProperties = [dict copy];
        
        // TODO: kVTDecompressionPropertyKey_PixelTransferProperties

        arOutputSetting[AVVideoDecompressionPropertiesKey] = decompressionProperties;
    }
}

- (NSMutableDictionary<NSString*,id>*)videoCompressionSettingFor:(AVMovieTrack *)track
{
    //
    NSDictionary* compressionProperties = nil;
    NSArray* proresFamily = @[@"ap4h", @"apch", @"apcn", @"apcs", @"apco"];
    if ([proresFamily containsObject:self.videoFourcc]) {
        // ProRes family
    } else {
        compressionProperties = @{AVVideoAverageBitRateKey:@(self.videoBitRate)};
    }
    
    NSDictionary* cleanAperture = nil;
    NSDictionary* pixelAspectRatio = nil;
    NSDictionary* nclc = nil;
    
    CGSize trackDimensions = track.naturalSize;
    NSArray* descArray = track.formatDescriptions;
    if (descArray.count > 0) {
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)(descArray[0]);
        trackDimensions = CMVideoFormatDescriptionGetPresentationDimensions(desc, FALSE, FALSE);
        
        NSNumber* fieldCount = nil;
        NSString* fieldDetail = nil;
        
        CFPropertyListRef cfExtCA = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_CleanAperture);
        if (cfExtCA != NULL) {
            NSDictionary* extCA = (__bridge NSDictionary*)cfExtCA;
            NSNumber* width = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureWidth];
            NSNumber* height = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureHeight];
            NSNumber* hOffset = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureHorizontalOffset];
            NSNumber* vOffset = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureVerticalOffset];
            
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            dict[AVVideoCleanApertureWidthKey] = width;
            dict[AVVideoCleanApertureHeightKey] = height;
            dict[AVVideoCleanApertureHorizontalOffsetKey] = hOffset;
            dict[AVVideoCleanApertureVerticalOffsetKey] = vOffset;
            
            cleanAperture = dict;
        }
        
        CFPropertyListRef cfExtPA = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_PixelAspectRatio);
        if (cfExtPA != NULL) {
            NSDictionary* extPA = (__bridge NSDictionary*)cfExtPA;
            NSNumber* hSpacing = (NSNumber*)extPA[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing];
            NSNumber* vSpacing = (NSNumber*)extPA[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing];
            
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            dict[AVVideoPixelAspectRatioHorizontalSpacingKey] = hSpacing;
            dict[AVVideoPixelAspectRatioVerticalSpacingKey] = vSpacing;
            
            pixelAspectRatio = dict;
        }
        
        if (self.copyNCLC) {
            CFPropertyListRef cfExtCP = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_ColorPrimaries);
            CFPropertyListRef cfExtTF = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_TransferFunction);
            CFPropertyListRef cfExtMX = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_YCbCrMatrix);
            if (cfExtCP && cfExtTF && cfExtMX) {
                NSString* colorPrimaries = (__bridge NSString*) cfExtCP;
                NSString* transferFunction = (__bridge NSString*) cfExtTF;
                NSString* ycbcrMatrix = (__bridge NSString*) cfExtMX;
                
                NSMutableDictionary* dict = [NSMutableDictionary dictionary];
                dict[AVVideoColorPrimariesKey] = colorPrimaries;
                dict[AVVideoTransferFunctionKey] = transferFunction;
                dict[AVVideoYCbCrMatrixKey] = ycbcrMatrix;
                
                nclc = dict;
            }
        }
        
        if (self.copyField) {
            CFPropertyListRef cfExtFC = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldCount);
            CFPropertyListRef cfExtFD = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldDetail);
            if (cfExtFC && cfExtFD) {
                fieldCount = (__bridge NSNumber*)cfExtFC;
                fieldDetail = (__bridge NSString*)cfExtFD;
            }
        }
        
        if (fieldCount || fieldDetail) {
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            
            if (self.copyField && fieldCount && fieldDetail) {
                dict[(__bridge NSString*)kVTCompressionPropertyKey_FieldCount] = fieldCount;
                dict[(__bridge NSString*)kVTCompressionPropertyKey_FieldDetail] = fieldDetail;
            }
            
            if (compressionProperties) {
                [dict addEntriesFromDictionary:compressionProperties];
            }
            compressionProperties = dict;
        }
    }
    
    // destination
    NSMutableDictionary* awInputSetting = [NSMutableDictionary dictionary];
    awInputSetting[AVVideoCodecKey] = self.videoFourcc;
    awInputSetting[AVVideoWidthKey] = @(trackDimensions.width);
    awInputSetting[AVVideoHeightKey] = @(trackDimensions.height);
    if (compressionProperties) {
        awInputSetting[AVVideoCompressionPropertiesKey] = compressionProperties;
    }
    
    if (cleanAperture) {
        awInputSetting[AVVideoCleanApertureKey] = cleanAperture;
    }
    if (pixelAspectRatio) {
        awInputSetting[AVVideoPixelAspectRatioKey] = pixelAspectRatio;
    }
    if (nclc) {
        awInputSetting[AVVideoColorPropertiesKey] = nclc;
    }
    return awInputSetting;
}

- (void) prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    if (self.videoEncode == FALSE) {
        [self prepareCopyChannelWith:movie from:ar to:aw of:AVMediaTypeVideo];
        return;
    }
    
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeVideo]) {
        // source
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        [self addDecommpressionPropertiesOf:track setting:arOutputSetting];
        arOutputSetting[(__bridge NSString*)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_422YpCbCr8);
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        [ar addOutput:arOutput];
        
        //
        NSMutableDictionary<NSString*,id> * awInputSetting = [self videoCompressionSettingFor:track];
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                         outputSettings:awInputSetting];
        awInput.mediaTimeScale = track.naturalTimeScale;
        [aw addInput:awInput];
        
        // channel
        SBChannel* sbcVideo = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                      consumerME:(MEInput*)awInput
                                                         TrackID:track.trackID];
        [sbChannels addObject:sbcVideo];
    }
}

- (void) prepareVideoMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw
{
    for (AVMovieTrack* track in [movie tracksWithMediaType:AVMediaTypeVideo]) {
        //
        NSString* key = keyForTrackID(track.trackID);
        //NSDictionary* managers = self.managers[key];
        MEManager* mgr = self.managers[key];
        if (!mgr) continue;

        // Capture source track's format description extensions
        CMFormatDescriptionRef desc =  (__bridge CMFormatDescriptionRef)track.formatDescriptions[0];
        CFDictionaryRef extensions =  CMFormatDescriptionGetExtensions(desc);
        mgr.sourceExtensions = extensions;
        
        int32_t ts = track.naturalTimeScale;
        mgr.mediaTimeScale = ts;
        
        // source from
        NSMutableDictionary<NSString*,id>* arOutputSetting = [NSMutableDictionary dictionary];
        [self addDecommpressionPropertiesOf:track setting:arOutputSetting];
        arOutputSetting[(__bridge NSString*)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_422YpCbCr8);
        AVAssetReaderOutput* arOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                                                                                   outputSettings:arOutputSetting];
        [ar addOutput:arOutput];
        
        // source to
        MEInput* meInput = [MEInput inputWithManager:mgr];
        
        // source channel
        SBChannel* sbcMEInput = [SBChannel sbChannelWithProducerME:(MEOutput*)arOutput
                                                        consumerME:meInput
                                                           TrackID:track.trackID];
        [sbChannels addObject:sbcMEInput];
        
        /* ========================================================================================== */
        
        // destination from
        MEOutput* meOutput = [MEOutput outputWithManager:mgr];
        
        // destination to
        NSMutableDictionary<NSString*,id>* awInputSetting;
        if (self.videoEncode == FALSE) {
            awInputSetting = nil; // passthru writing
        } else {
            awInputSetting = [self videoCompressionSettingFor:track]; // transcode using AVFoundation
        }
        
        AVAssetWriterInput* awInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                         outputSettings:awInputSetting];
        awInput.mediaTimeScale = track.naturalTimeScale;
        [aw addInput:awInput];
        
        // destination channel
        SBChannel* sbcMEOutput = [SBChannel sbChannelWithProducerME:(MEOutput*)meOutput
                                                         consumerME:(MEInput*)awInput
                                                            TrackID:track.trackID];
        [sbChannels addObject:sbcMEOutput];
    }
}

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder (paramParser)

- (BOOL) copyOtherMedia
{
    NSNumber* numCopyOtherMedia = param[kCopyOtherMediaKey];
    BOOL copyOtherMedia = (numCopyOtherMedia != nil) ? numCopyOtherMedia.boolValue : FALSE;
    return copyOtherMedia;
}

- (BOOL) audioEncode
{
    NSNumber* numAudioEncode = param[kAudioEncodeKey];
    BOOL audioEncode = (numAudioEncode != nil) ? numAudioEncode.boolValue : FALSE;
    return audioEncode;
}

- (NSString*) audioFourcc
{
    NSString* fourcc = param[kAudioCodecKey];
    return fourcc;
}

- (int) audioBitRate
{
    NSNumber* numAudioKbps = param[kAudioKbpsKey];
    float targetKbps = (numAudioKbps != nil) ? numAudioKbps.floatValue : 128;
    int targetBitrate = (int)(targetKbps * 1000);
    return targetBitrate;
}

- (int) lpcmDepth
{
    NSNumber* numPCMDepth = param[kLPCMDepthKey];
    int lpcmDepth = (numPCMDepth != nil) ? numPCMDepth.intValue : 16;
    return lpcmDepth;
}

- (BOOL) videoEncode
{
    NSNumber* numVideoEncode = param[kVideoEncodeKey];
    BOOL videoEncode = (numVideoEncode != nil) ? numVideoEncode.boolValue : FALSE;
    return videoEncode;
}

- (NSString*) videoFourcc
{
    NSString* fourcc = param[kVideoCodecKey];
    return fourcc;
}

- (int) videoBitRate
{
    NSNumber* numVideoKbps = param[kVideoKbpsKey];
    float targetKbps = (numVideoKbps != nil) ? numVideoKbps.floatValue : 2500;
    int targetBitRate = (int)(targetKbps * 1000);
    return targetBitRate;
}

- (BOOL) copyField
{
    NSNumber* numCopyField = param[kCopyFieldKey];
    BOOL copyField = (numCopyField != nil) ? numCopyField.boolValue : FALSE;
    return copyField;
}

- (BOOL) copyNCLC
{
    NSNumber* numCopyNCLC = param[kCopyNCLCKey];
    BOOL copyNCLC = (numCopyNCLC != nil) ? numCopyNCLC.boolValue : FALSE;
    return copyNCLC;
}

uint32_t formatIDFor(NSString* fourCC)
{
    uint32_t result = 0;
    const char* str = [fourCC cStringUsingEncoding:NSASCIIStringEncoding];
    if (str && strlen(str) >= 4) {
        uint32_t c0 = str[0], c1 = str[1], c2 = str[2], c3 = str[3];
        result = (c0<<24) + (c1<<16) + (c2<<8) + (c3);
    }
    return result;
}

- (uint32_t) audioFormatID
{
    return formatIDFor(self.audioFourcc);
}

- (uint32_t) videoFormatID
{
    return formatIDFor(self.videoFourcc);
}

- (uint32_t) audioChannelLayoutTag {
    NSNumber* numTag = param[kAudioChannelLayoutTagKey];
    return (numTag != nil) ? numTag.unsignedIntValue : 0;
}

@end

NS_ASSUME_NONNULL_END
