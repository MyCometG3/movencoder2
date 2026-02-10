//
//  MEManager.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEManager.h"
#import "MEManager+Queuing.h"
#import "MEManager+Pipeline.h"
#import "MEManager+SampleBuffer.h"
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
        
        // Propagate initial log level to pipelines (so FFmpeg av_log_set_level gets INFO)
        self.log_level = log_level;
        
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

/* =================================================================================== */
// MARK: - Internal alias forwarding (IO bridge clarity)
/* =================================================================================== */

- (BOOL)appendSampleBufferInternal:(CMSampleBufferRef)sb { return [self appendSampleBuffer:sb]; }
- (BOOL)isReadyForMoreMediaDataInternal { return [self isReadyForMoreMediaData]; }
- (void)markAsFinishedInternal { [self markAsFinished]; }
- (void)requestMediaDataWhenReadyOnQueueInternal:(dispatch_queue_t)queue usingBlock:(RequestHandler)block { [self requestMediaDataWhenReadyOnQueue:queue usingBlock:block]; }
- (CMTimeScale)mediaTimeScaleInternal { return self.mediaTimeScale; }
- (void)setMediaTimeScaleInternal:(CMTimeScale)mediaTimeScale { self.mediaTimeScale = mediaTimeScale; }
- (CGSize)naturalSizeInternal { return self.naturalSize; }
- (void)setNaturalSizeInternal:(CGSize)naturalSize { self.naturalSize = naturalSize; }
- (nullable CMSampleBufferRef)copyNextSampleBufferInternal { return [self copyNextSampleBuffer]; }
- (AVMediaType)mediaTypeInternal { return self.mediaType; }

/* =================================================================================== */
// MARK: - Internal frame accessors
/* =================================================================================== */

- (void *)input
{
    return input;
}

- (void)setInput:(void *)frame
{
    input = (AVFrame *)frame;
}

- (struct AVFrameColorMetadata *)cachedColorMetadata
{
    return &cachedColorMetadata;
}

- (struct AVFPixelFormatSpec *)pxl_fmt_filter
{
    return &pxl_fmt_filter;
}

- (void *)inputQueueKeyPtr
{
    return inputQueueKey;
}

- (void)setInputQueueKeyPtr:(void *)ptr
{
    inputQueueKey = ptr;
}

- (void *)outputQueueKeyPtr
{
    return outputQueueKey;
}

- (void)setOutputQueueKeyPtr:(void *)ptr
{
    outputQueueKey = ptr;
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

@end

NS_ASSUME_NONNULL_END
