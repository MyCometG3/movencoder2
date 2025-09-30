//
//  MEManager.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
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

#import "MECommon.h"
#import "MEManager.h"
#import "MEUtils.h"
#import "MESecureLogging.h"
#import "Config/MEVideoEncoderConfig.h"
#import "MEErrorFormatter.h"
#import "MEFilterPipeline.h"
#import "MEEncoderPipeline.h"
#import "MESampleBufferFactory.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NSString* const kMEVECodecNameKey = @"codecName";           // ffmpeg -c:v libx264
NSString* const kMEVECodecOptionsKey = @"codecOptions";     // NSDictionary of AVOptions for codec ; ffmpeg -h encoder=libx264
NSString* const kMEVEx264_paramsKey = @"x264_params";       // NSString ; ffmpeg -x264-params "x264option_strings"
NSString* const kMEVEx265_paramsKey = @"x265_params";       // NSString ; ffmpeg -x265-params "x264option_strings"
NSString* const kMEVECodecFrameRateKey = @"codecFrameRate"; // NSValue of CMTime ; ffmpeg -r 30000:1001
NSString* const kMEVECodecWxHKey = @"codecWxH";             // NSValue of NSSize ; ffmpeg -s 720x480
NSString* const kMEVECodecPARKey = @"codecPAR";             // NSValue of NSSize ; ffmpeg -aspect 16:9
NSString* const kMEVFFilterStringKey = @"filterString";     // NSString ; ffmpeg -vf "filter_graph_strings"
NSString* const kMEVECodecBitRateKey = @"codecBitRate";     // NSNumber ; ffmpeg -b:v 2.5M
NSString* const kMEVECleanApertureKey = @"cleanAperture";   // NSValue of NSRect ; convert as ffmpeg -crop-left/right/top/bottom

enum AVPixelFormat pix_fmt_list[] = { AV_PIX_FMT_YUV444P, AV_PIX_FMT_YUV422P, AV_PIX_FMT_YUV420P, AV_PIX_FMT_UYVY422, AV_PIX_FMT_NONE };

static const char* const kMEInputQueue = "MEManager.MEInputQueue";
static const char* const kMEOutputQueue = "MEManager.MEOutputQueue";

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEManager ()
{
    AVFrame* input ;
    
    struct AVFPixelFormatSpec pxl_fmt_filter;  // Pixel format spec for filter
    
    struct AVFrameColorMetadata cachedColorMetadata;  // Cache for input color metadata
    
    void* inputQueueKey;
    void* outputQueueKey;
}

// Pipeline components
@property (nonatomic, strong, readwrite) MEFilterPipeline *filterPipeline;
@property (nonatomic, strong, readwrite) MEEncoderPipeline *encoderPipeline;
@property (nonatomic, strong, readwrite) MESampleBufferFactory *sampleBufferFactory;

// Synchronization semaphores as private properties (delegated to pipeline components)
@property (readonly, nonatomic, strong) dispatch_semaphore_t timestampGapSemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t filterReadySemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t encoderReadySemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t eagainDelaySemaphore;

// Input frame management (still needed for pipeline coordination)
- (BOOL)prepareInputFrameWith:(CMSampleBufferRef)sb;

// private
@property (nonatomic, strong) dispatch_queue_t inputQueue;
@property (nonatomic, strong) dispatch_block_t inputBlock;
@property (nonatomic, strong) dispatch_queue_t outputQueue;
@property (atomic) BOOL queueing;  // Made atomic - accessed across input/output queues
@property (atomic) CMTimeScale time_base;  // Made atomic - accessed across input/output queues
@property (atomic, strong, nullable) __attribute__((NSObject)) CMFormatDescriptionRef desc;  // Made atomic - for output CMSampleBufferRef
@property (atomic, strong, nullable) __attribute__((NSObject)) CFDictionaryRef pbAttachments; // Made atomic - for CVImageBufferRef

// private atomic - state management that coordinates across pipeline components
@property (atomic, readwrite) int64_t lastEnqueuedPTS; // Made atomic - for Filter, accessed across queues
@property (atomic, readwrite) int64_t lastDequeuedPTS; // Made atomic - for Filter, accessed across queues

// private properties for metadata caching
@property (atomic, assign) BOOL colorMetadataCached;

// public atomic redefined
@property (readwrite) BOOL failed;
@property (readwrite) AVAssetWriterStatus writerStatus; // MEInput
@property (readwrite) AVAssetReaderStatus readerStatus; // MEOutput

// Configuration management (now delegated to encoder pipeline)
@property (atomic, strong, readwrite, nullable) MEVideoEncoderConfig *videoEncoderConfig; // lazy from videoEncoderSetting
@property (atomic, assign) BOOL configIssuesLogged;

// Computed properties that delegate to pipeline components
@property (readonly) BOOL videoFilterIsReady;
@property (readonly) BOOL videoFilterEOF;
@property (readonly) BOOL filteredValid;
@property (readonly) BOOL videoEncoderIsReady;
@property (readonly) BOOL videoEncoderEOF;
@property (readonly) BOOL videoFilterFlushed;
@property (readonly) BOOL videoEncoderFlushed;

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEManager

//
@synthesize pbAttachments;
// Synchronization semaphores
@synthesize timestampGapSemaphore;
@synthesize filterReadySemaphore;
@synthesize encoderReadySemaphore;
@synthesize eagainDelaySemaphore;
// public atomic redefined
@synthesize failed;
@synthesize readerStatus;
@synthesize writerStatus;
// public
@synthesize videoFilterString;
@synthesize videoEncoderSetting;
@synthesize videoEncoderConfig;
@synthesize sourceExtensions;
@synthesize initialDelayInSec;
@synthesize verbose = _verbose;
@synthesize log_level;

- (instancetype) init
{
    self = [super init];
    if (self) {
        readerStatus = AVAssetReaderStatusUnknown;
        writerStatus = AVAssetWriterStatusUnknown;
        initialDelayInSec = 1.0;
        
        log_level = AV_LOG_INFO;
        
        // Initialize pipeline components
        _filterPipeline = [[MEFilterPipeline alloc] init];
        _encoderPipeline = [[MEEncoderPipeline alloc] init];
        _sampleBufferFactory = [[MESampleBufferFactory alloc] init];
        
        // Initialize synchronization semaphores (delegate to components where appropriate)
        timestampGapSemaphore = _filterPipeline.timestampGapSemaphore;
        filterReadySemaphore = _filterPipeline.filterReadySemaphore;
        encoderReadySemaphore = _encoderPipeline.encoderReadySemaphore;
        eagainDelaySemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (void)setVideoEncoderSetting:(NSMutableDictionary * _Nullable)setting
{
    // One-time verbose summary of configuration issues (if any)
    if (self.verbose && !self.configIssuesLogged) {
        MEVideoEncoderConfig *cfgOnce = self.videoEncoderConfig;
        if (cfgOnce.issues.count) {
            SecureLogf(@"[MEManager][ConfigSummary] %lu issue(s)", (unsigned long)cfgOnce.issues.count);
            for (NSString *msg in cfgOnce.issues) {
                SecureDebugLogf(@"[MEManager][ConfigIssue] %@", msg);
            }
            self.configIssuesLogged = YES;
        }
    }

    videoEncoderSetting = setting;
    videoEncoderConfig = nil; // reset cache
    
    // Sync to encoder pipeline and sample buffer factory
    self.encoderPipeline.videoEncoderSetting = setting;
    self.sampleBufferFactory.videoEncoderSetting = setting;
}

- (void)setVideoFilterString:(NSString * _Nullable)filterString
{
    videoFilterString = filterString;
    
    // Sync to filter pipeline
    self.filterPipeline.filterString = filterString;
}

- (void)setVerbose:(BOOL)verbose
{
    _verbose = verbose;
    
    // Sync to all pipeline components
    self.filterPipeline.verbose = verbose;
    self.encoderPipeline.verbose = verbose;
    self.sampleBufferFactory.verbose = verbose;
}

- (void)setLog_level:(int)logLevel
{
    log_level = logLevel;
    
    // Sync to all pipeline components
    self.filterPipeline.logLevel = logLevel;
    self.encoderPipeline.logLevel = logLevel;
}

- (void)setSourceExtensions:(CFDictionaryRef _Nullable)extensions
{
    sourceExtensions = extensions;
    
    // Sync to encoder pipeline
    self.encoderPipeline.sourceExtensions = extensions;
}

/* =================================================================================== */
// MARK: - Computed properties that delegate to pipeline components
/* =================================================================================== */

- (BOOL)videoFilterIsReady
{
    return self.filterPipeline.isReady;
}

- (BOOL)videoFilterEOF
{
    return self.filterPipeline.isEOF;
}

- (BOOL)filteredValid
{
    return self.filterPipeline.hasValidFilteredFrame;
}

- (BOOL)videoEncoderIsReady
{
    return self.encoderPipeline.isReady;
}

- (BOOL)videoEncoderEOF
{
    return self.encoderPipeline.isEOF;
}

- (BOOL)videoFilterFlushed
{
    // For now, we consider filter flushed when EOF is reached
    return self.filterPipeline.isEOF;
}

- (BOOL)videoEncoderFlushed
{
    return self.encoderPipeline.isFlushed;
}

// Delegate time base to pipeline components
- (CMTimeScale)timeBase
{
    return self.filterPipeline.timeBase;
}

- (void)setTimeBase:(CMTimeScale)timeBase
{
    self.filterPipeline.timeBase = timeBase;
    self.encoderPipeline.timeBase = timeBase;
    self.sampleBufferFactory.timeBase = timeBase;
}

// Delegate lastDequeuedPTS to filter pipeline
- (int64_t)lastDequeuedPTS
{
    return [self.filterPipeline lastDequeuedPTS];
}

- (void)setLastDequeuedPTS:(int64_t)pts
{
    [self.filterPipeline setLastDequeuedPTS:pts];
}

- (MEVideoEncoderConfig * _Nullable)videoEncoderConfig
{
    @synchronized (self) {
        if (!videoEncoderConfig && videoEncoderSetting) {
            videoEncoderConfig = [MEVideoEncoderConfig configFromLegacyDictionary:videoEncoderSetting error:NULL];
            // Sync to encoder pipeline
            self.encoderPipeline.videoEncoderConfig = videoEncoderConfig;
        }
        return videoEncoderConfig;
    }
}

- (void)setVideoEncoderConfig:(MEVideoEncoderConfig * _Nullable)config
{
    @synchronized (self) {
        videoEncoderConfig = config; // explicit setter to satisfy atomic contract
    }
}

+ (instancetype) new
{
    return [[self alloc] init];
}

- (void) dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    av_frame_free(&input);

    // Cleanup pipeline components
    [self.filterPipeline cleanup];
    [self.encoderPipeline cleanup];
    [self.sampleBufferFactory cleanup];
    
    self.pbAttachments = nil;
}

/* =================================================================================== */
// MARK: - Utility methods / inline functions
/* =================================================================================== */

static inline BOOL useVideoFilter(MEManager *obj) {
    return (obj.videoFilterString != NULL);
}

static inline BOOL useVideoEncoder(MEManager *obj) {
    return (obj.videoEncoderSetting != NULL);
}

static inline BOOL uselibx264(MEManager *obj) {
    if (!useVideoEncoder(obj)) return FALSE;
    MEVideoEncoderConfig *cfg = obj.videoEncoderConfig;
    return (cfg && cfg.codecKind == MEVideoCodecKindX264);
}

static inline BOOL uselibx265(MEManager *obj) {
    if (!useVideoEncoder(obj)) return FALSE;
    MEVideoEncoderConfig *cfg = obj.videoEncoderConfig;
    return (cfg && cfg.codecKind == MEVideoCodecKindX265);
}

static inline long waitOnSemaphore(dispatch_semaphore_t semaphore, uint64_t timeoutMilliseconds) {
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, timeoutMilliseconds * NSEC_PER_MSEC);
    return dispatch_semaphore_wait(semaphore, timeout);
}

- (dispatch_queue_t) inputQueue
{
    if (!_inputQueue) {
        _inputQueue = dispatch_queue_create(kMEInputQueue, DISPATCH_QUEUE_SERIAL);
        inputQueueKey = &inputQueueKey;
        void* unused = (__bridge void*)self;
        dispatch_queue_set_specific(_inputQueue, inputQueueKey, unused, NULL);
    }
    return _inputQueue;
}

- (dispatch_queue_t) outputQueue
{
    if (!_outputQueue) {
        _outputQueue = dispatch_queue_create(kMEOutputQueue, DISPATCH_QUEUE_SERIAL);
        outputQueueKey = &outputQueueKey;
        void* unused = (__bridge void*)self;
        dispatch_queue_set_specific(_outputQueue, outputQueueKey, unused, NULL);
    }
    return _outputQueue;
}

- (void) input_sync:(dispatch_block_t)block /* unused */
{
    dispatch_queue_t queue = self.inputQueue;
    void * key = inputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_sync(queue, block);
    }
}

- (void) input_async:(dispatch_block_t)block
{
    dispatch_queue_t queue = self.inputQueue;
    void * key = inputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_async(queue, block);
    }
}

- (void) output_sync:(dispatch_block_t)block
{
    dispatch_queue_t queue = self.outputQueue;
    void * key = outputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_sync(queue, block);
    }
}

- (void) output_async:(dispatch_block_t)block /* unused */
{
    dispatch_queue_t queue = self.outputQueue;
    void * key = outputQueueKey;
    assert (queue && key);
    if (dispatch_get_specific(key)) {
        block(); // do sync operation
    } else {
        dispatch_async(queue, block);
    }
}

/**
 Setup VideoEncoder using parameters from CMSampleBuffer
 Now delegates to MEEncoderPipeline component.

 @param sb CMSampleBuffer
 @return TRUE if success. FALSE if fail.
 */
- (BOOL)prepareVideoEncoderWith:(CMSampleBufferRef _Nullable)sb
{
    // Sync time base before preparation if needed
    if (self.timeBase == 0 && sb) {
        AVRational timebase_q = {1, 1};
        if (CMSBGetTimeBase(sb, &timebase_q)) {
            self.timeBase = timebase_q.den;
        }
    }
    
    // If filter pipeline is active and a filtered frame is not yet available, delay encoder initialization
    if (self.filterPipeline.filterString.length > 0 && !self.filteredValid) {
        return NO; // retry later
    }

    // Delegate to encoder pipeline (prefer filtered frame if available)
    void *filteredFrame = NULL;
    BOOL hasValidFilteredFrame = NO;
    if (self.filteredValid) {
        filteredFrame = [self.filterPipeline filteredFrame];
        hasValidFilteredFrame = YES;
    }
    return [self.encoderPipeline prepareVideoEncoderWith:sb 
                                           filteredFrame:filteredFrame
                                     hasValidFilteredFrame:hasValidFilteredFrame];
}

/**
 Setup VideoFilter using parameters from CMSampleBuffer
 Now delegates to MEFilterPipeline component.

 @param sb CMSampleBuffer
 @return TRUE if success. FALSE if fail.
 */
- (BOOL)prepareVideoFilterWith:(CMSampleBufferRef)sb
{
    // Sync time base before preparation
    if (self.timeBase == 0) {
        AVRational timebase_q = {1, 1};
        if (CMSBGetTimeBase(sb, &timebase_q)) {
            self.timeBase = timebase_q.den;
        }
    }
    
    // Delegate to filter pipeline
    return [self.filterPipeline prepareVideoFilterWith:sb];
}

/**
 * Prepare input AVFrame from CMSampleBuffer and its CVImageBuffer.
 * 
 * FRAME OWNERSHIP: This method manages the internal 'input' frame lifecycle.
 * The input frame is owned by MEManager and is reused across calls.
 * av_frame_unref() is called to clear previous data before reuse.
 *
 * @param sb CMSampleBuffer to extract frame data from
 * @return TRUE if success, FALSE if fail
 */
- (BOOL)prepareInputFrameWith:(CMSampleBufferRef)sb
{
    // get input stream timebase
    if (self.timeBase == 0) { // fallback
        AVRational timebase_q = {1, 1};
        if (CMSBGetTimeBase(sb, &timebase_q)) {
            self.timeBase = timebase_q.den;
        } else {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot validate timebase.");
            goto end;
        }
    }
    
    // prepare AVFrame for input
    if (!input) {
        input = av_frame_alloc(); // allocate frame
        if (!input) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot allocate a video frame.");
            goto end;
        }
    }
    
    // setup AVFrame for input
    if (input) {
        // apply widthxheight
        int width, height;
        BOOL result = CMSBGetWidthHeight(sb, &width, &height);
        if (!result) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot get rectangle values.");
            goto end;
        }
        
        // Clear previous frame data before reuse (proper frame lifecycle management)
        av_frame_unref(input);
        AVFrameReset(input);
        
        // Obtain pixel format spec (lost after refactor) so that input->format matches source buffer
        if (!(CMSBGetPixelFormatSpec(sb, &pxl_fmt_filter) && pxl_fmt_filter.avf_id != 0)) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot validate pixel_format.");
            goto end;
        }
        input->format = pxl_fmt_filter.ff_id;
        input->width = width;
        input->height = height;
        input->time_base = av_make_q(1, self.timeBase);
        
        // allocate new input buffer
        int ret = AVERROR_UNKNOWN;
        ret = av_frame_get_buffer(input, 0); // allocate new buffer
        if (ret < 0) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot allocate data for the video frame.");
            goto end;
        }
        
        ret = av_frame_make_writable(input);
        if (ret < 0) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot make the video frame writable");
            goto end;
        }
        
        // fill input AVFrame parameters
        result = CMSBCopyParametersToAVFrame(sb, input, self.timeBase);
        if (!result) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot fill property values.");
            goto end;
        }
        
        // Try to update them from original Sample Buffer extensions.
        {
            int color_primaries = 0;
            if (CMSBGetColorPRI_FDE(sourceExtensions, &color_primaries)) {
                input->color_primaries = color_primaries;
            }
            
            int color_trc = 0;
            if (CMSBGetColorTRC_FDE(sourceExtensions, &color_trc)) {
                input->color_trc = color_trc;
            }
            
            int colorspace = 0;
            if (CMSBGetColorSPC_FDE(sourceExtensions, &colorspace)) {
                input->colorspace = colorspace;
            }
            
            int fieldCount = 1;
            int top_field_first = 0;
            if (CMSBGetFieldInfo_FDE(sourceExtensions, &fieldCount, &top_field_first)) {
                input->flags &= ~AV_FRAME_FLAG_INTERLACED;
                input->flags &= ~AV_FRAME_FLAG_TOP_FIELD_FIRST;
                if (fieldCount == 2) {
                    input->flags |= AV_FRAME_FLAG_INTERLACED;
                    if (top_field_first) {
                        input->flags |= AV_FRAME_FLAG_TOP_FIELD_FIRST;
                    }
                }
            }
        }
        
        // Cache color metadata from input frame (first sample only)
        if (!self.colorMetadataCached) {
            cachedColorMetadata.color_range = input->color_range;
            cachedColorMetadata.color_primaries = input->color_primaries;
            cachedColorMetadata.color_trc = input->color_trc;
            cachedColorMetadata.colorspace = input->colorspace;
            cachedColorMetadata.chroma_location = input->chroma_location;
            self.colorMetadataCached = YES;
        }
        
        // copy image data into input AVFrame buffer
        result = CMSBCopyImageBufferToAVFrame(sb, input);
        if (!result) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot copy image buffer.");
            goto end;
        }

        return TRUE;
    }
    
end:
    return FALSE;
}


/**
 Create CMSampleBuffer using filtered output from VideoFilter

 @return CMSampleBuffer
 */
-(nullable CMSampleBufferRef)createUncompressedSampleBuffer
{
    // Delegate to sample buffer factory with filtered frame from filter pipeline
    void *filteredFrame = [self.filterPipeline filteredFrame];
    if (!filteredFrame) {
        SecureErrorLogf(@"[MEManager] ERROR: No filtered frame available.");
        return NULL;
    }
    
    return [self.sampleBufferFactory createUncompressedSampleBufferFromFilteredFrame:filteredFrame];
}

/**
 Create CMSampleBuffer using output from VideoEncoder

 @return CMSampleBuffer
 */
-(nullable CMSampleBufferRef)createCompressedSampleBuffer
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

/* =================================================================================== */
// MARK: - For MEInput - queue SB from previous AVAssetReaderOutput to MEInput
/* =================================================================================== */

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
    if (self->input == NULL) goto error;
    
    BOOL inputFrameIsReady = (self->input->format != AV_PIX_FMT_NONE);
    int64_t newPTS = self->input->pts;
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
        void *frameToSend = inputFrameIsReady ? self->input : NULL;
        BOOL success = [self.filterPipeline pushFrameToFilter:frameToSend withResult:ret];
        
        if (success && *ret == 0) {
            if (inputFrameIsReady) {
                // Filter pipeline keeps reference (AV_BUFFERSRC_FLAG_KEEP_REF), 
                // so caller must unref the original frame
                av_frame_unref(self->input);
                self.lastEnqueuedPTS = newPTS;
                // Signal timestamp gap semaphore when PTS is updated
                dispatch_semaphore_signal(self.timestampGapSemaphore);
#if 0
                float pts0 = (float)self.lastEnqueuedPTS/self.timeBase;
                float pts1 = (float)[self.filterPipeline lastDequeuedPTS]/self.timeBase;
                float diff = fabsf(pts1-pts0);
                SecureDebugLogf(@"[Filter] enqueued:%8.2f, dequeued:%8.2f, diffInSec:%5.2f", pts0, pts1, diff );
#endif
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
        void *frameToSend = inputFrameIsReady ? self->input : NULL;
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

- (BOOL)appendSampleBuffer:(CMSampleBufferRef)sb
{
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
    av_frame_unref(self->input);
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

- (void)requestMediaDataWhenReadyOnQueue:(dispatch_queue_t)queue usingBlock:(RequestHandler)block
{
    self.inputQueue = queue;
    self.inputBlock = block;

    inputQueueKey = &inputQueueKey;
    void* unused = (__bridge void*)self;
    dispatch_queue_set_specific(_inputQueue, inputQueueKey, unused, NULL);
}

- (CMTimeScale)mediaTimeScale
{
    return self.timeBase;
}

- (void)setMediaTimeScale:(CMTimeScale)mediaTimeScale
{
    self.timeBase = mediaTimeScale;
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
    NSDictionary *setting = [videoEncoderSetting copy];
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

/* =================================================================================== */
// MARK: - For MEOutput - queue SB from MEOutput to next AVAssetWriterInput
/* =================================================================================== */

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
        
        //CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        
        self.queueing = initialQueueing(self);
        if (!self.queueing) {
            goto error;
        }
        
        //CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
        //SecureDebugLogf(@"[MEManager] initial delayed = %.3f", (end - start));
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
                                //SecureLogf(@"[MEManager] Filter graph detected EOF.");
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
                            if (filteredFrame) {
                                AVFrameFillMetadataFromCache((AVFrame *)filteredFrame, &self->cachedColorMetadata);
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
                                // SecureLogf(@"[MEManager] Encoder detected EOF");
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
                    if (countEAGAIN == 2) {                     // Try next ququeing after delay
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
                            // SecureLogf(@"[MEManager] Encoder detected EOF");
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
                    if (countEAGAIN == 1) {                     // Try next ququeing after delay
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
                            //SecureLogf(@"[MEManager] Filter graph detected EOF.");
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
                    if (countEAGAIN == 1) {                     // Try next ququeing after delay
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

- (AVMediaType)mediaType
{
    return AVMediaTypeVideo;
}

@end

NS_ASSUME_NONNULL_END
