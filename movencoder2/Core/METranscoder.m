//
//  METranscoder.m
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

#import "METranscoder+Internal.h"
#import "MESecureLogging.h"
#import "MEProgressUtil.h"

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
NSString* const kAudioVolumeKey = @"audioVolume";

static const char* const kControlQueueLabel = "movencoder.controlQueue";
static const char* const kProcessQueueLabel = "movencoder.processQueue";

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder

// MARK: - 

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
            // Initialize centralized configuration and keep legacy param proxy
            self.transcodeConfig = [[METranscodeConfiguration alloc] init];
            param = self.transcodeConfig.encodingParams;
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

/* =================================================================================== */
// MARK: - validation methods
/* =================================================================================== */

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
    if (!mgr || !path) {
        return NO;
    }
    
    BOOL fileExists = [mgr fileExistsAtPath:path];
    
    if (fileExists) {
        // If file exists, try to test write access by attempting to open it for writing
        NSFileHandle* fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fileHandle) {
            [fileHandle closeFile];
            return YES;
        } else {
            // If direct file access fails, check if we can delete and recreate
            return [mgr isDeletableFileAtPath:path];
        }
    } else {
        // If file doesn't exist, test if we can create it by attempting to create a temporary file
        @autoreleasepool {
            NSString* parentDir = [path stringByDeletingLastPathComponent];
            NSString* filename = [path lastPathComponent];
            NSString* tempPath = [parentDir stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.tmp.%d", filename, getpid()]];
            
            // Try to create a temporary file to test write access
            NSError* error = nil;
            BOOL success = [@"test" writeToFile:tempPath
                                     atomically:NO
                                       encoding:NSUTF8StringEncoding
                                          error:&error];
        
            if (success) {
                // Clean up the temporary file
                [mgr removeItemAtPath:tempPath error:nil];
                return YES;
            } else {
                // Fallback to basic directory write check
                return [mgr isWritableFileAtPath:parentDir];
            }
        }
    }
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

/* =================================================================================== */
// MARK: - public methods
/* =================================================================================== */

- (void) registerMEManager:(MEManager *)meManager forTrackID:(CMPersistentTrackID)trackID
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

- (void) registerMEAudioConverter:(MEAudioConverter *)meAudioConverter forTrackID:(CMPersistentTrackID)trackID
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

- (void)setVerbose:(BOOL)v
{
    verbose = v; // keep property ivar in sync
    self.transcodeConfig.verbose = v;
}

- (void)setParam:(NSMutableDictionary *)paramIn
{
    NSMutableDictionary *normalizedParams = paramIn ?: [NSMutableDictionary dictionary];
    param = normalizedParams;
    self.transcodeConfig.encodingParams = normalizedParams;
}

- (void)setCallbackQueue:(dispatch_queue_t _Nullable)queue
{
    _callbackQueue = queue;
    self.transcodeConfig.callbackQueue = queue;
}

- (void)setStartCallback:(dispatch_block_t _Nullable)block
{
    _startCallback = block;
    self.transcodeConfig.startCallback = block;
}

- (void)setProgressCallback:(progress_block_t _Nullable)block
{
    _progressCallback = block;
    // Bridge to internal configuration type
    self.transcodeConfig.progressCallback = (MEProgressBlock)block;
}

- (void)setCompletionCallback:(dispatch_block_t _Nullable)block
{
    _completionCallback = block;
    self.transcodeConfig.completionCallback = block;
}

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder (export)

#pragma mark - Error Helper

static inline NSError* MECreateError(NSString* description, NSString* reason, NSInteger code) {
    if (!description) description = @"unknown description";
    if (!reason) reason = @"unknown failureReason";
    NSString *domain = @"com.MyCometG3.movencoder2.ErrorDomain";
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : description,
                               NSLocalizedFailureReasonErrorKey : reason};
    return [NSError errorWithDomain:domain code:code userInfo:userInfo];
}

// MARK: - private properties

- (dispatch_queue_t _Nullable) controlQueue
{
    if (!_controlQueue) {
        controlQueueKey = &controlQueueKey;
        void *unused = (__bridge void*)self;
        _controlQueue = dispatch_queue_create(kControlQueueLabel, DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_controlQueue, controlQueueKey, unused, NULL);
    }
    return _controlQueue;
}

- (dispatch_queue_t _Nullable) processQueue
{
    if (!_processQueue) {
        processQueueKey = &processQueueKey;
        void *unused = (__bridge void*)self;
        _processQueue = dispatch_queue_create(kProcessQueueLabel, DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_processQueue, processQueueKey, unused, NULL);
    }
    return _processQueue;
}

- (CFAbsoluteTime) timeElapsed
{
    CFAbsoluteTime ts0 = self.timeStamp0;
    CFAbsoluteTime ts1 = self.timeStamp1;
    if (ts0 && ts1) return (ts1 - ts0);
    if (ts0 > 0 && ts1 == 0) return (CFAbsoluteTimeGetCurrent() - ts0);
    return 0;
}

// MARK: - export methods

- (BOOL) exportCustomOnError:(NSError **)error
{
    self.timeStamp0 = CFAbsoluteTimeGetCurrent();
    self.timeStamp1 = 0;

    BOOL useME = NO;
    BOOL useAC = NO;
    AVMutableMovie* mov = self.inMovie;
    AVAssetWriter* aw = nil;
    AVAssetReader* ar = nil;
    BOOL finish = NO;

    if (![self me_prepareExportSession:error useME:&useME useAC:&useAC]) {
        goto finalize;
    }

    if (![self me_configureWriterAndPrepareChannelsWithMovie:mov useME:useME useAC:useAC error:error]) {
        goto finalize;
    }

    aw = self.assetWriter;
    ar = self.assetReader;

    if (![self me_startIOAndWaitWithReader:ar writer:aw finish:&finish error:error]) {
        goto finalize;
    }

    [self me_finalizeSessionWithFinish:finish error:error];

finalize:
    if (self.finalSuccess) {
        SecureLog(@"[METranscoder] Export session completed.");
    } else if (self.cancelled) {
        SecureLog(@"[METranscoder] Export session cancelled.");
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
        SecureErrorLogf(@"[METranscoder] ERROR: Export session failed. Error details: %@", [self.finalError description]);
    }

    self.timeStamp1 = CFAbsoluteTimeGetCurrent();
    SecureLogf(@"[METranscoder] elapsed: %.2f sec", self.timeElapsed);
    [self cleanupTemporaryFilesForOutput:self.outputURL];
    self.writerIsBusy = FALSE;
    return self.finalSuccess;
}

#pragma mark - Export helper steps

- (BOOL)me_prepareExportSession:(NSError * _Nullable * _Nullable)error useME:(BOOL*)useME useAC:(BOOL*)useAC
{
    if (self.writerIsBusy) {
        NSError* err = nil;
        [self post:[NSString stringWithFormat:@"%s (%d)", __PRETTY_FUNCTION__, __LINE__]
            reason:@"Multiple call is not allowed."
              code:paramErr
                to:&err];
        self.finalError = err;
        if (error) *error = err;
        return NO;
    }

    NSFileManager *fm = [NSFileManager new];
    if ([fm fileExistsAtPath:[outputURL path]]) {
        if (![fm removeItemAtURL:outputURL error:nil]) {
            NSError* err = nil;
            [self post:[NSString stringWithFormat:@"%s (%d)", __PRETTY_FUNCTION__, __LINE__]
                reason:@"Output file path is not writable."
                  code:paramErr
                    to:&err];
            self.finalError = err;
            if (error) *error = err;
            return NO;
        }
    }

    AVMutableMovie* mov = self.inMovie;
    if (!( CMTIME_IS_VALID(self.startTime) && CMTIME_IS_VALID(self.endTime) )) {
        self.startTime = kCMTimeZero;
        self.endTime = mov.duration;
    } else {
        int compResult = CMTIME_COMPARE_INLINE(self.startTime, <, self.endTime);
        int compResult2 = CMTIME_COMPARE_INLINE(kCMTimeZero, <=, self.startTime);
        if (!(compResult && compResult2)) {
            self.startTime = kCMTimeZero;
            self.endTime = mov.duration;
        }
    }
    CMTimeRange maxRange = CMTimeRangeMake(self.startTime, self.endTime);
    self.startTime = CMTimeClampToRange(self.startTime, maxRange);
    self.endTime = CMTimeClampToRange(self.endTime, maxRange);

    self.writerIsBusy = TRUE;

    *useME = [self hasVideoMEManagers];
    *useAC = [self hasAudioMEConverters];

    if (![self prepareRW]) {
        NSError* err = nil;
        [self post:[NSString stringWithFormat:@"%s (%d)", __PRETTY_FUNCTION__, __LINE__]
            reason:@"Either AVAssetReader or AVAssetWriter is not available."
              code:paramErr
                to:&err];
        self.finalError = err;
        if (error) *error = err;
        return NO;
    }

    SecureLog(@"[METranscoder] Export session started.");
    // Update consolidated time range in configuration (non-breaking)
    CMTimeRange tr;
    if (CMTIME_IS_VALID(self.startTime) && CMTIME_IS_VALID(self.endTime)) {
        CMTime duration = CMTimeSubtract(self.endTime, self.startTime);
        tr = CMTimeRangeMake(self.startTime, duration);
    } else {
        tr = kCMTimeRangeInvalid;
    }
    self.transcodeConfig.timeRange = tr;
    return YES;
}

- (BOOL)me_configureWriterAndPrepareChannelsWithMovie:(AVMutableMovie*)mov useME:(BOOL)useME useAC:(BOOL)useAC error:(NSError * _Nullable * _Nullable)error
{
    AVAssetWriter* aw = self.assetWriter;
    AVAssetReader* ar = self.assetReader;

    dispatch_sync(self.processQueue, ^{
        aw.movieTimeScale = mov.timescale;
        aw.movieFragmentInterval = kCMTimeInvalid;
        aw.shouldOptimizeForNetworkUse = TRUE;
    });

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
    return YES;
}

- (BOOL)me_startIOAndWaitWithReader:(AVAssetReader*)ar writer:(AVAssetWriter*)aw finish:(BOOL*)finish error:(NSError * _Nullable * _Nullable)error
{
    __block BOOL arStarted = FALSE;
    __block BOOL awStarted = FALSE;
    dispatch_sync(self.processQueue, ^{
        arStarted = [ar startReading];
        awStarted = [aw startWriting];
    });
    if (!(arStarted && awStarted)) {
        __block NSError* err = nil;
        dispatch_sync(self.processQueue, ^{
            err = (!arStarted ? ar.error : aw.error);
            [ar cancelReading];
            [aw cancelWriting];
        });
        self.finalSuccess = FALSE;
        self.finalError = err;
        [self rwDidFinished];
        if (error) *error = err;
        return NO;
    }

    dispatch_sync(self.processQueue, ^{
        [aw startSessionAtSourceTime:startTime];
    });

    [self rwDidStarted];

    dispatch_group_t dg = dispatch_group_create();
    NSArray<SBChannel*>* channelArray = self.sbChannels;
    for (SBChannel* sbc in channelArray) {
        dispatch_group_enter(dg);
        dispatch_block_t handler = ^{ dispatch_group_leave(dg); };
        [sbc startWithDelegate:self completionHandler:handler];
    }

    __weak typeof(self) wself = self;
    __weak typeof(AVAssetReader*) war = ar;
    __weak typeof(AVAssetWriter*) waw = aw;
    dispatch_semaphore_t waitSem = dispatch_semaphore_create(0);

    dispatch_group_notify(dg, self.processQueue, ^{
        BOOL finalize = TRUE;
        BOOL cancelled = wself.cancelled;
        if (!cancelled) {
            BOOL arFailed = (war.status == AVAssetReaderStatusFailed);
            if (arFailed) {
                wself.finalSuccess = FALSE;
                wself.finalError = war.error;
                finalize = FALSE;
            }
        }
        if (finalize) {
            [waw endSessionAtSourceTime:wself.endTime];
            [waw finishWritingWithCompletionHandler:^{
                dispatch_async(wself.processQueue, ^{
                    BOOL awFailed = (waw.status == AVAssetWriterStatusFailed);
                    if (awFailed) {
                        wself.finalSuccess = FALSE;
                        wself.finalError = waw.error ?: war.error;
                    } else {
                        *finish = !cancelled;
                    }
                    dispatch_semaphore_signal(waitSem);
                });
            }];
        } else {
            dispatch_semaphore_signal(waitSem);
        }
    });

    dispatch_semaphore_wait(waitSem, DISPATCH_TIME_FOREVER);

    if (*finish) {
        self.finalSuccess = TRUE;
        self.finalError = nil;
    }
    return YES;
}

- (BOOL)me_finalizeSessionWithFinish:(BOOL)finish error:(NSError * _Nullable * _Nullable)error
{
    [self rwDidFinished];
    return (error == NULL || *error == nil);
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

// MARK: - callback support

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
        float progress = [MEProgressUtil progressPercentForSampleBuffer:sb start:self.startTime end:self.endTime];
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

// MARK: - utility methods

- (BOOL) post:(NSString*)description
       reason:(NSString*)failureReason
         code:(NSInteger)result
           to:(NSError * _Nullable * _Nullable)error
{
    if (error) {
        *error = MECreateError(description, failureReason, result);
        return YES;
    }
    return NO;
}

- (BOOL) prepareRW
{
    __block NSError *error = nil;
    __block AVAssetReader* assetReader = nil;
    __block AVAssetWriter* assetWriter = nil;
    dispatch_sync(self.processQueue, ^{
        assetReader = [[AVAssetReader alloc] initWithAsset:self.inMovie
                                                     error:&error];
        if (error) return;
        assetWriter = [[AVAssetWriter alloc] initWithURL:self.outputURL
                                                fileType:AVFileTypeQuickTimeMovie
                                                   error:&error];
    });
    
    if (!assetReader) {
        SecureErrorLog(@"[METranscoder] ERROR: Failed to init AVAssetReader");
        if (error)
            self.finalError = error;
        return FALSE;
    }
    if (!assetWriter) {
        SecureErrorLog(@"[METranscoder] ERROR: Failed to init AVAssetWriter");
        if (error)
            self.finalError = error;
        return FALSE;
    }
    
    self.assetReader = assetReader;
    self.assetWriter = assetWriter;
    return TRUE;
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

- (void) cleanupTemporaryFilesForOutput:(NSURL*)outputURL
{
    if (!outputURL) return;

    static const NSTimeInterval kMETempFileMaxAge = 60.0; // seconds
    static NSString* const kMETempFileMarker = @".sb-";   // fragment inside temp file name

    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* outputDirURL = [outputURL URLByDeletingLastPathComponent];
    NSString* outputFilename = [outputURL lastPathComponent];

    NSError* error = nil;
    NSArray<NSURLResourceKey>* keys = @[NSURLContentModificationDateKey, NSURLNameKey];
    NSArray<NSURL*>* dirContents = [fm contentsOfDirectoryAtURL:outputDirURL
                                     includingPropertiesForKeys:keys
                                                        options:NSDirectoryEnumerationSkipsHiddenFiles
                                                          error:&error];
    if (!dirContents) {
        SecureErrorLogf(@"[METranscoder] Failed to list directory contents for temp file cleanup: %@", error.localizedDescription);
        return;
    }

    NSArray<NSURL*>* sortedFiles = [dirContents sortedArrayUsingComparator:^NSComparisonResult(NSURL* _Nonnull url1, NSURL* _Nonnull url2) {
        NSDate* date1 = nil; NSDate* date2 = nil;
        [url1 getResourceValue:&date1 forKey:NSURLContentModificationDateKey error:nil];
        [url2 getResourceValue:&date2 forKey:NSURLContentModificationDateKey error:nil];
        return [date2 compare:date1];
    }];

    NSDate* now = [NSDate date];
    NSMutableArray<NSURL*>* candidateFiles = [NSMutableArray array];

    for (NSURL* fileURL in sortedFiles) {
        NSString* filename = nil; NSDate* modDate = nil;
        if ([fileURL getResourceValue:&filename forKey:NSURLNameKey error:nil] &&
            [fileURL getResourceValue:&modDate forKey:NSURLContentModificationDateKey error:nil]) {
            if (modDate && [now timeIntervalSinceDate:modDate] <= kMETempFileMaxAge) {
                if ([filename hasPrefix:outputFilename] && [filename containsString:kMETempFileMarker]) {
                    [candidateFiles addObject:fileURL];
                }
            }
        }
    }

    for (NSURL* fileURL in candidateFiles) {
        NSString* filename = [fileURL lastPathComponent];
        BOOL removed = [fm removeItemAtURL:fileURL error:&error];
        if (removed) {
            SecureLogf(@"[METranscoder] Cleaned up temporary file: %@", filename);
        } else {
            SecureErrorLogf(@"[METranscoder] Failed to remove temporary file %@: %@", filename, error.localizedDescription);
        }
    }
}

@end

NS_ASSUME_NONNULL_END
