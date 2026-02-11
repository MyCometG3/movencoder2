//
//  MEManager+SampleBuffer.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MEManager+SampleBuffer.h"
#import "MEManager+Internal.h"
#import "MEManager+Queuing.h"
#import "MEManager+Pipeline.h"
#import "MECommon.h"
#import "MEUtils.h"
#import "MESecureLogging.h"
#import "MEFilterPipeline.h"
#import "MEEncoderPipeline.h"
#import "MESampleBufferFactory.h"
#import "Config/MEVideoEncoderConfig.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

/* =================================================================================== */
// MARK: - Static helper functions
/* =================================================================================== */

static inline BOOL useVideoFilter(MEManager *obj) {
    return (obj.videoFilterString != NULL);
}

static inline BOOL useVideoEncoder(MEManager *obj) {
    return (obj.videoEncoderSetting != NULL);
}

static inline long waitOnSemaphore(dispatch_semaphore_t semaphore, uint64_t timeoutMilliseconds) {
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, timeoutMilliseconds * NSEC_PER_MSEC);
    return dispatch_semaphore_wait(semaphore, timeout);
}

static BOOL shouldStopQueueing(MEManager* self) {
    if (self.failed) goto error;
    AVAssetWriterStatus status = self.writerStatus;
    if (status != AVAssetWriterStatusWriting &&
        status != AVAssetWriterStatusUnknown) {
        return TRUE;                                        // No more input allowed
    }

    if (self.videoFilterIsReady) {
        return (self.videoFilterEOF ? TRUE : FALSE);
    }
    if (self.videoEncoderIsReady) {
        return (self.videoEncoderEOF ? TRUE : FALSE);
    }
    
    return FALSE; // continue processing
    
error:
    SecureErrorLogf(@"[MEManager] ERROR: either filter or encoder is not ready.");
    self.failed = TRUE;
    self.writerStatus = AVAssetWriterStatusFailed;
    return TRUE;
}

static void enqueueToME(MEManager *self, int *ret) {
    if (self.failed) goto error;
    AVFrame *input = (AVFrame *)[self input];
    if (input == NULL) goto error;
    
    BOOL inputFrameIsReady = (input->format != AV_PIX_FMT_NONE);
    int64_t newPTS = input->pts;
    if (useVideoFilter(self)) {
        if (self.videoFilterFlushed) return;
        if (!self.videoFilterIsReady) {
            SecureErrorLogf(@"[MEManager] ERROR: the filtergraph is not ready");
            goto error;
        }
        if (self.videoFilterEOF) {
            SecureErrorLogf(@"[MEManager] ERROR: the filtergraph reached EOF.");
            goto error;
        }
        
        // Delegate to filter pipeline to push frame
        void *frameToSend = inputFrameIsReady ? input : NULL;
        BOOL success = [self.filterPipeline pushFrameToFilter:frameToSend withResult:ret];
        
        if (success && *ret == 0) {
            if (inputFrameIsReady) {
                // Filter pipeline keeps reference (AV_BUFFERSRC_FLAG_KEEP_REF), 
                // so caller must unref the original frame
                av_frame_unref(input);
                self.lastEnqueuedPTS = newPTS;
                // Signal timestamp gap semaphore when PTS is updated
                dispatch_semaphore_signal(self.timestampGapSemaphore);
            } else {
                // Set videoFilterFlushed through computed property (this should be delegated to filter pipeline)
            }
            self.writerStatus = AVAssetWriterStatusWriting;
            return;
        } else {
            if (*ret == AVERROR(EAGAIN)) {
                return;
            } else if (*ret == AVERROR_EOF) {
                return;
            } else {
                SecureErrorLogf(@"[MEManager] ERROR: av_buffersrc_add_frame() returned %08X", *ret);
            }
        }
    } else {
        if (self.videoEncoderFlushed) return;
        if (!self.videoEncoderIsReady) {
            SecureErrorLogf(@"[MEManager] ERROR: the encoder is not ready.");
            goto error;
        }
        if (self.videoEncoderEOF) {
            SecureErrorLogf(@"[MEManager] ERROR: the encoder reached EOF.");
            goto error;
        }
        
        // Delegate to encoder pipeline to send frame
        void *frameToSend = inputFrameIsReady ? input : NULL;
        BOOL success = [self.encoderPipeline sendFrameToEncoder:frameToSend withResult:ret];
        
        if (success && *ret == 0) {
            // Note: Do NOT call av_frame_unref here - sendFrameToEncoder takes ownership
            // and handles the unref internally
            self.writerStatus = AVAssetWriterStatusWriting;
            return;
        } else {
            if (*ret == AVERROR(EAGAIN)) {
                return;
            } else if (*ret == AVERROR_EOF) {
                return;
            } else if (!success) {
                SecureErrorLogf(@"[MEManager] ERROR: Failed to send frame to encoder.");
            }
        }
    }
    
error:
    self.failed = TRUE;
    self.writerStatus = AVAssetWriterStatusFailed;
}

static void pullFilteredFrame(MEManager *self, int *ret) {
    // Delegate to filter pipeline
    BOOL success = [self.filterPipeline pullFilteredFrameWithResult:ret];
    if (!success && *ret < 0) {
        if (*ret != AVERROR(EAGAIN) && *ret != AVERROR_EOF) {
            self.failed = TRUE;
            self.writerStatus = AVAssetWriterStatusFailed;
        }
    }
}

static void pushFilteredFrame(MEManager *self, int *ret) {
    if (self.videoEncoderFlushed) return;
    if (self.videoEncoderEOF) return;
    
    if (!self.videoEncoderIsReady) {                        // Prepare encoder after filtergraph
        // The filter graph operates asynchronously — initialize the encoder only after a filtered frame
        // has been dequeued and validated. Return EAGAIN to indicate that no frame is ready yet.
        // The caller should retry when filteredValid is TRUE.
        if (!self.filteredValid) {
            *ret = AVERROR(EAGAIN);
            return;
        }
        BOOL result = [self prepareVideoEncoderWith:NULL];  // Pass NULL to use filtered frame
        if (!result || !self.videoEncoderIsReady) {
            SecureErrorLogf(@"[MEManager] ERROR: Failed to initialize the encoder");
            goto error;
        }
    }
    
    if (self.filteredValid) {                               // Push filtered frame into encoder
        void *filteredFrame = [self.filterPipeline filteredFrame];
        BOOL success = [self.encoderPipeline sendFrameToEncoder:filteredFrame withResult:ret];
        if (success && *ret == 0) {
            [self.filterPipeline resetFilteredFrame];
            return;
        } else if (*ret == AVERROR(EAGAIN)) {               // encoder is busy - Try again later
            return;
        } else if (*ret == AVERROR_EOF) {
            return;
        } else if (!success) {
            SecureErrorLogf(@"[MEManager] ERROR: failed to send frame to encoder.");
        }
    } else if (self.videoFilterEOF) {                       // Push flush frame into encoder
        BOOL success = [self.encoderPipeline flushEncoderWithResult:ret];
        if (success && *ret == 0) {
            return;
        } else if (*ret == AVERROR(EAGAIN)) {               // encoder is busy - Try again later
            return;
        } else if (*ret == AVERROR_EOF) {
            return;
        } else if (!success) {
            SecureErrorLogf(@"[MEManager] ERROR: failed to flush the encoder.");
        }
    } else {
        SecureDebugLogf(@"[MEManager] Force retry (pushFilteredFrame)");
        *ret = AVERROR(EAGAIN);
        return;
    }
    
error:
    self.failed = TRUE;
    self.readerStatus = AVAssetReaderStatusFailed;
}

static void pullEncodedPacket(MEManager *self, int *ret) {
    if (self.videoEncoderEOF) return;
    
    if (!self.videoEncoderIsReady) {
        *ret = AVERROR_UNKNOWN;
        SecureErrorLogf(@"[MEManager] ERROR: the encoder is not ready.");
        goto error;
    }
    
    // Delegate to encoder pipeline
    BOOL success = [self.encoderPipeline receivePacketFromEncoderWithResult:ret];
    if (success && *ret == 0) {
        return;
    } else if (*ret == AVERROR(EAGAIN)) {                   // Encoder requests more input
        return;
    } else if (*ret == AVERROR_EOF) {                       // Fully flushed out
        self.readerStatus = AVAssetReaderStatusCompleted;
        return;
    } else if (!success) {
        SecureErrorLogf(@"[MEManager] ERROR: Failed to receive packet from encoder.");
    }

error:
    self.failed = TRUE;
    self.readerStatus = AVAssetReaderStatusFailed;
}

static BOOL initialQueueing(MEManager *self) {
    if (self.inputBlock && self.inputQueue) {
        // Validate semaphores are initialized
        if (!self.eagainDelaySemaphore || !self.filterReadySemaphore || !self.encoderReadySemaphore) {
            SecureErrorLogf(@"[MEManager] ERROR: Semaphores not properly initialized.");
            return FALSE;
        }
        
        // Try initial queueing here
        [self input_async:self.inputBlock];
        
        // wait till ready
        double delayLimitInSec = MAX(self.initialDelayInSec, 30.0);
        CFAbsoluteTime limit = CFAbsoluteTimeGetCurrent() + delayLimitInSec;
        
        // Use semaphore wait instead of av_usleep for initial delay
        int64_t timeoutMilliseconds = self.initialDelayInSec * MSEC_PER_SEC;
        waitOnSemaphore(self.eagainDelaySemaphore, timeoutMilliseconds);
        
        if (useVideoFilter(self)) {
            do {
                if (self.failed) break;
                if (self.videoFilterIsReady) break;
                // Use semaphore wait instead of av_usleep for filter ready check
                waitOnSemaphore(self.filterReadySemaphore, 100);
            } while (CFAbsoluteTimeGetCurrent() < limit);
            if (!self.videoFilterIsReady) {
                SecureErrorLogf(@"[MEManager] ERROR: Filter graph is not ready.");
                goto error;
            }
        } else {
            do {
                if (self.failed) break;
                if (self.videoEncoderIsReady) break;
                // Use semaphore wait instead of av_usleep for encoder ready check
                waitOnSemaphore(self.encoderReadySemaphore, 100);
            } while (CFAbsoluteTimeGetCurrent() < limit);
            if (!self.videoEncoderIsReady) {
                SecureErrorLogf(@"[MEManager] ERROR: Encoder is not ready.");
                goto error;
            }
        }
        return (!self.failed);
    } else {
        SecureErrorLogf(@"[MEManager] ERROR: input queue or block is invalid.");
    }
    
error:
    return FALSE;
}

/* =================================================================================== */
// MARK: - Category implementation
/* =================================================================================== */

@implementation MEManager (SampleBuffer)

-(nullable CMSampleBufferRef)createUncompressedSampleBuffer CF_RETURNS_RETAINED
{
    // Delegate to sample buffer factory with filtered frame from filter pipeline
    void *filteredFrame = [self.filterPipeline filteredFrame];
    if (!filteredFrame) {
        SecureErrorLogf(@"[MEManager] ERROR: No filtered frame available.");
        return NULL;
    }
    
    return [self.sampleBufferFactory createUncompressedSampleBufferFromFilteredFrame:filteredFrame];
}

-(nullable CMSampleBufferRef)createCompressedSampleBuffer CF_RETURNS_RETAINED
{
    // Delegate to sample buffer factory with encoded packet from encoder pipeline
    void *encodedPacket = [self.encoderPipeline encodedPacket];
    void *codecContext = [self.encoderPipeline codecContext];
    
    if (!encodedPacket) {
        SecureErrorLogf(@"[MEManager] ERROR: No encoded packet available.");
        return NULL;
    }
    
    return [self.sampleBufferFactory createCompressedSampleBufferFromPacket:encodedPacket 
                                                                codecContext:codecContext
                                                          videoEncoderConfig:self.videoEncoderConfig];
}

- (BOOL)appendSampleBuffer:(CMSampleBufferRef _Nullable)sb
{
    AVFrame *input = (AVFrame *)[self input];

    if (self.failed) goto error;
    AVAssetWriterStatus status = self.writerStatus;
    if (status != AVAssetWriterStatusWriting &&
        status != AVAssetWriterStatusUnknown) {
        return FALSE; // No more input allowed
    }
    if (useVideoFilter(self)) {                         // Verify if filtergraph is ready
        if (!self.videoFilterIsReady) {                 // Prepare filter graph
            assert(sb != NULL); // prepareVideoFilterWith cannot accept NULL input
            BOOL result = [self prepareVideoFilterWith:sb];
            if (!result || !self.videoFilterIsReady) {
                SecureErrorLogf(@"[MEManager] ERROR: Failed to prepare the filter graph");
                goto error;
            }
        }
        if (self.videoFilterFlushed) {
            return FALSE;
        }
    } else {                                            // verify if encoder is ready
        if (!self.videoEncoderIsReady) {                // use new CMSampleBuffer
            // prepareVideoEncoderWith CAN accept NULL input
            BOOL result = [self prepareVideoEncoderWith:sb];
            if (!result || !self.videoEncoderIsReady) {
                SecureErrorLogf(@"[MEManager] ERROR: Failed to prepare the encoder");
                goto error;
            }
        }
        if (self.videoEncoderFlushed) {
            return FALSE;
        }
    }
    
    if (sb) {                                               // Create AVFrame from CMSampleBuffer
        BOOL result = [self prepareInputFrameWith:sb];
        if (!result) {
            SecureErrorLogf(@"[MEManager] ERROR: Failed to prepare the input frame");
            goto error;
        }
    } else {
        // Treat as flush request
    }
    
    {
        __block int ret = 0;
        int64_t gapLimitInSec = self.timeBase * 10;
        do {
            @autoreleasepool {
                // Wait until the input/output timestamp gap is less than 10 seconds.
                while (llabs(self.lastEnqueuedPTS - self.lastDequeuedPTS) >= gapLimitInSec) {
                    // Use semaphore wait instead of busy loop with usleep
                    waitOnSemaphore(self.timestampGapSemaphore, 50);
                    if (self.failed) return NO;
                }
                
                // Feed a new frame into the filter/encoder context
                [self output_sync:^{
                    enqueueToME(self, &ret);
                }];
                
                // Abort on unexpected errors (other than EAGAIN)
                if (self.failed || (ret < 0 && ret != AVERROR(EAGAIN))) {
                    SecureErrorLogf(@"[MEManager] ERROR: Failed to enqueue the input frame (ret=%d)", ret);
                    return NO;
                }
                
                // Retry enqueue if EAGAIN is returned
                if (ret == AVERROR(EAGAIN)) {
                    // Use semaphore wait instead of av_usleep for backoff
                    waitOnSemaphore(self.eagainDelaySemaphore, 50);
                }
            }
        } while (ret == AVERROR(EAGAIN));
        return TRUE;
    }
error:
    // Clean up input frame on error to prevent memory leaks
    if (input) {
        av_frame_unref(input);
    }
    self.failed = TRUE;
    self.writerStatus = AVAssetWriterStatusFailed;
    return FALSE;
}

- (BOOL)isReadyForMoreMediaData
{
    return !shouldStopQueueing(self);
}

- (void)markAsFinished
{
    SecureLogf(@"[MEManager] End of input stream detected.");
    [self output_sync:^{
        int ret = 0;
        enqueueToME(self, &ret);
    }];
}

- (nullable CMSampleBufferRef)copyNextSampleBuffer
{
    __block int ret = 0;
    CMSampleBufferRef sb = NULL;

    if (self.failed) goto error;
    AVAssetWriterStatus status = self.writerStatus;
    if (status != AVAssetWriterStatusWriting &&
        status != AVAssetWriterStatusUnknown) {
        return NULL; // No more output allowed
    }
    
    if (!self.queueing) {
        if (self.verbose) {
            SecureDebugLogf(@"[MEManager] videoEncoderSettings = \n%@", [self.videoEncoderSetting description]);
            SecureDebugLogf(@"[MEManager] videoFilterString = %@", self.videoFilterString);
        }
        
        self.queueing = initialQueueing(self);
        if (!self.queueing) {
            goto error;
        }
    }
    
    if (useVideoEncoder(self)) {                            // encode => output
        if (useVideoFilter(self)) {                         // filtered => encode => output
            int countEAGAIN = 0;
            do {
                @autoreleasepool {
                    countEAGAIN = 0;
                    if (!self.videoFilterEOF) {
                        [self output_sync:^{
                            pullFilteredFrame(self, &ret);      // Pull filtered frame from the filtergraph
                        }];
                        if (self.failed) goto error;
                        if (ret < 0) {
                            if (ret == AVERROR_EOF) {
                                ret = 0;
                            }
                            if (ret == AVERROR(EAGAIN)) {
                                countEAGAIN++;                  // filtergraph requires more frame
                                ret = 0;
                            }
                            if (ret < 0) {
                                SecureErrorLogf(@"[MEManager] ERROR: Filter graph detected: %d", ret);
                                goto error;
                            }
                        }
                        
                        // Fill missing metadata from cached input metadata as fallback
                        if (self.filteredValid && self.colorMetadataCached) {
                            void *filteredFrame = [self.filterPipeline filteredFrame];
                            struct AVFrameColorMetadata *cachedColorMetadata = [self cachedColorMetadata];
                            if (filteredFrame) {
                                AVFrameFillMetadataFromCache((AVFrame *)filteredFrame, cachedColorMetadata);
                            }
                        }
                    }
                    {
                        [self output_sync:^{
                            pushFilteredFrame(self, &ret);      // Push filtered frame into encoder
                            if (self.failed) return;
                            if (ret < 0) return;
                            pullEncodedPacket(self, &ret);      // Pull compressed output from encoder
                        }];
                        if (self.failed) goto error;
                        if (ret < 0) {
                            if (ret == AVERROR_EOF) {
                                ret = 0;
                            }
                            if (ret == AVERROR(EAGAIN)) {
                                countEAGAIN++;                  // encoder requires more frame
                                ret = 0;
                            }
                            if (ret < 0) {
                                SecureErrorLogf(@"[MEManager] ERROR: Filter graph detected: %d", ret);
                                goto error;
                            }
                        }
                    }
                    if (countEAGAIN == 2) {                     // Try next queueing after delay
                        waitOnSemaphore(self.eagainDelaySemaphore, 50);
                        if (self.failed) goto error;
                    }
                }
            } while(countEAGAIN > 0);                       // loop - blocking
        } else {                                            // encode => output
            int countEAGAIN = 0;
            do {
                @autoreleasepool {
                    countEAGAIN = 0;
                    [self output_sync:^{
                        pullEncodedPacket(self, &ret);          // Pull compressed output from encoder
                    }];
                    if (self.failed) goto error;
                    if (ret < 0) {
                        if (ret == AVERROR_EOF) {
                            ret = 0;
                        }
                        if (ret == AVERROR(EAGAIN)) {
                            countEAGAIN++;                      // encoder requires more frame
                            ret = 0;
                        }
                        if (ret < 0) {
                            SecureErrorLogf(@"[MEManager] ERROR: Encoder detected: %d", ret);
                            break;
                        }
                    }
                    if (countEAGAIN == 1) {                     // Try next queueing after delay
                        waitOnSemaphore(self.eagainDelaySemaphore, 50);
                        if (self.failed) goto error;
                    }
                }
            } while(countEAGAIN > 0);                       // loop - blocking
        }
        if (self.videoFilterEOF && self.videoEncoderEOF) {
            SecureLogf(@"[MEManager] End of output stream detected.");
            return NULL;
        }
        if (ret == 0) {
            sb = [self createCompressedSampleBuffer];       // Create CMSampleBuffer from encoded packet
            if (sb) {
                // Let the encoder pipeline handle the packet cleanup
                return sb;
            } else {
                SecureErrorLogf(@"[MEManager] ERROR: Failed to createCompressedSampleBuffer.");
            }
        } else {
            SecureErrorLogf(@"[MEManager] ERROR: Unable to createCompressedSampleBuffer.");
        }
    } else {                                                // filtered => output
        {
            int countEAGAIN = 0;
            do {
                @autoreleasepool {
                    countEAGAIN = 0;
                    [self output_sync:^{
                        pullFilteredFrame(self, &ret);          // Pull filtered frame from the filtergraph
                    }];
                    if (self.failed) {
                        goto error;
                    } else {
                        if (ret == AVERROR_EOF) {
                            ret = 0;
                        }
                        if (ret == AVERROR(EAGAIN)) {
                            countEAGAIN++;                      // filtergraph requires more frame
                            ret = 0;
                        }
                        if (ret < 0) {
                            SecureErrorLogf(@"[MEManager] ERROR: Filter graph detected: %d", ret);
                            break;
                        }
                    }
                    if (countEAGAIN == 1) {                     // Try next queueing after delay
                        waitOnSemaphore(self.eagainDelaySemaphore, 50);
                        if (self.failed) {
                            goto error;
                        }
                    }
                }
            } while(countEAGAIN > 0);                       // loop - blocking
        }
        if (self.videoFilterEOF) {
            SecureLogf(@"[MEManager] End of output stream detected.");
            return NULL;
        }
        if (ret == 0) {
            sb = [self createUncompressedSampleBuffer];     // Create CMSampleBuffer from filtered frame
            if (sb) {
                [self.filterPipeline resetFilteredFrame];
                return sb;
            } else {
                SecureErrorLogf(@"[MEManager] ERROR: Failed to createUncompressedSampleBuffer.");
            }
        } else {
            SecureErrorLogf(@"[MEManager] ERROR: Unable to createUncompressedSampleBuffer.");
        }
    }
    
error:
    self.failed = TRUE;
    return NULL;
}

- (CGSize)naturalSize
{
    // Prefer type-safe config
    MEVideoEncoderConfig *cfg = self.videoEncoderConfig;
    if (cfg.hasDeclaredSize && cfg.hasPixelAspect) {
        NSSize rawSize = cfg.declaredSize;
        NSSize pixAspect = cfg.pixelAspect;
        CGFloat naturalWidth = rawSize.width * pixAspect.width / pixAspect.height;
        CGFloat naturalHeight = rawSize.height;
        return NSMakeSize(naturalWidth, naturalHeight);
    }
    // Fallback to legacy dictionary (compatibility)
    NSDictionary *setting = [self.videoEncoderSetting copy];
    if (setting) {
        NSValue *rawSizeValue = setting[kMEVECodecWxHKey];
        NSValue *pixAspectValue = setting[kMEVECodecPARKey];
        if (rawSizeValue && pixAspectValue) {
            NSSize rawSize = [rawSizeValue sizeValue];
            NSSize pixAspect = [pixAspectValue sizeValue];
            CGFloat naturalWidth = rawSize.width * pixAspect.width / pixAspect.height;
            CGFloat naturalHeight = rawSize.height;
            return NSMakeSize(naturalWidth, naturalHeight);
        }
    }
    
    return CGSizeZero;
}

- (void)setNaturalSize:(CGSize)naturalSize
{
    // TODO: Ignore for now
    SecureErrorLogf(@"[MEManager] ERROR: -setNaturalSize: is unsupported.");
}

- (AVMediaType)mediaType
{
    return AVMediaTypeVideo;
}

@end

NS_ASSUME_NONNULL_END
