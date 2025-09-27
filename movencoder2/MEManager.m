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
#import "MEVideoEncoderConfig.h"

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
    struct AVFPixelFormatSpec pxl_fmt_filter;
    AVFilterContext *buffersink_ctx;
    AVFilterContext *buffersrc_ctx;
    AVFilterGraph *filter_graph;

    struct AVFPixelFormatSpec pxl_fmt_encode;
    AVCodecContext* avctx;
    
    AVFrame* input ;
    AVFrame* filtered;
    AVPacket* encoded;
    
    struct AVFrameColorMetadata cachedColorMetadata;  // Cache for input color metadata
    BOOL colorMetadataCached;  // Flag to indicate if metadata is cached
    
    void* inputQueueKey;
    void* outputQueueKey;
}

// Synchronization semaphores as private properties
@property (readonly, nonatomic, strong) dispatch_semaphore_t timestampGapSemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t filterReadySemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t encoderReadySemaphore;
@property (readonly, nonatomic, strong) dispatch_semaphore_t eagainDelaySemaphore;

- (BOOL)prepareVideoEncoderWith:(CMSampleBufferRef _Nullable)sb;
- (BOOL)prepareVideoFilterWith:(CMSampleBufferRef)sb;
- (BOOL)prepareInputFrameWith:(CMSampleBufferRef)sb;
- (nullable CMSampleBufferRef)createUncompressedSampleBuffer CF_RETURNS_RETAINED;
- (nullable CMSampleBufferRef)createCompressedSampleBuffer CF_RETURNS_RETAINED;

// private
@property (nonatomic, strong) dispatch_queue_t inputQueue;
@property (nonatomic, strong) dispatch_block_t inputBlock;
@property (nonatomic, strong) dispatch_queue_t outputQueue;
@property (atomic) BOOL queueing;  // Made atomic - accessed across input/output queues
@property (atomic) CMTimeScale time_base;  // Made atomic - accessed across input/output queues
@property (atomic, strong, nullable) __attribute__((NSObject)) CMFormatDescriptionRef desc;  // Made atomic - for output CMSampleBufferRef
@property (atomic, strong, nullable) __attribute__((NSObject)) CVPixelBufferPoolRef cvpbpool;  // Made atomic - accessed across queues
@property (atomic, strong, nullable) __attribute__((NSObject)) CFDictionaryRef pbAttachments; // Made atomic - for CVImageBufferRef

// private atomic
@property (readwrite) BOOL videoFilterIsReady;
@property (readwrite) BOOL videoFilterEOF;
@property (readwrite) BOOL filteredValid;
@property (readwrite) BOOL videoEncoderIsReady;
@property (readwrite) BOOL videoEncoderEOF;
@property (readwrite) BOOL videoFilterFlushed;
@property (readwrite) BOOL videoEncoderFlushed;

@property (atomic, readwrite) int64_t lastEnqueuedPTS; // Made atomic - for Filter, accessed across queues
@property (atomic, readwrite) int64_t lastDequeuedPTS; // Made atomic - for Filter, accessed across queues

// public atomic redefined
@property (readwrite) BOOL failed;
@property (readwrite) AVAssetWriterStatus writerStatus; // MEInput
@property (readwrite) AVAssetReaderStatus readerStatus; // MEOutput

@property (atomic, strong, readwrite) MEVideoEncoderConfig *videoEncoderConfig; // lazy from videoEncoderSetting

@end

NS_ASSUME_NONNULL_END

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEManager

//
@synthesize time_base;
@synthesize desc;
@synthesize cvpbpool;
@synthesize pbAttachments;
// Synchronization semaphores
@synthesize timestampGapSemaphore;
@synthesize filterReadySemaphore;
@synthesize encoderReadySemaphore;
@synthesize eagainDelaySemaphore;
// private atomic
@synthesize videoFilterIsReady;
@synthesize videoFilterEOF;
@synthesize filteredValid;
@synthesize videoEncoderIsReady;
@synthesize videoEncoderEOF;
@synthesize videoFilterFlushed;
@synthesize videoEncoderFlushed;
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
@synthesize verbose;
@synthesize log_level;

- (instancetype) init
{
    self = [super init];
    if (self) {
        readerStatus = AVAssetReaderStatusUnknown;
        writerStatus = AVAssetWriterStatusUnknown;
        initialDelayInSec = 1.0;
        
        // default = 420 planar 8bit MPEG color range
        pxl_fmt_encode = AVFPixelFormatSpec420P;
        
        log_level = AV_LOG_INFO;
        
        // Initialize synchronization semaphores
        timestampGapSemaphore = dispatch_semaphore_create(0);
        filterReadySemaphore = dispatch_semaphore_create(0);
        encoderReadySemaphore = dispatch_semaphore_create(0);
        eagainDelaySemaphore = dispatch_semaphore_create(0);
    }
    return self;
}

- (void)setVideoEncoderSetting:(NSMutableDictionary *)setting
{
    videoEncoderSetting = setting;
    videoEncoderConfig = nil; // reset cache
}

- (MEVideoEncoderConfig *)videoEncoderConfig
{
    if (!videoEncoderConfig && videoEncoderSetting) {
        videoEncoderConfig = [MEVideoEncoderConfig configFromLegacyDictionary:videoEncoderSetting error:NULL];
    }
    return videoEncoderConfig;
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
    av_packet_free(&encoded);
    av_frame_free(&filtered);
    av_frame_free(&input);
    avcodec_free_context(&avctx);
    avfilter_graph_free(&filter_graph);

    self.desc = nil;
    self.cvpbpool = nil;
    self.pbAttachments = nil;
}

/* =================================================================================== */
// MARK: - Utility methods / inline functions
/* =================================================================================== */

static inline BOOL useVideoFilter(MEManager *obj) {
    return (obj->videoFilterString != NULL);
}

static inline BOOL useVideoEncoder(MEManager *obj) {
    return (obj->videoEncoderSetting != NULL);
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

 @param sb CMSampleBuffer
 @return TRUE if success. FALSE if fail.
 */
- (BOOL)prepareVideoEncoderWith:(CMSampleBufferRef _Nullable)sb
{
    int ret = 0;
    const AVCodec* codec = NULL;
    AVDictionary* opts = NULL;
    
    if (self.videoEncoderIsReady)
        return TRUE;
    if (!(videoEncoderSetting && videoEncoderSetting.count)) {
        SecureErrorLogf(@"[MEManager] ERROR: Invalid video encoder parameters.");
        goto end;
    }
    
    // Update log_level
    av_log_set_level(self.log_level);
    
    // Allocate encoder context
    {
        MEVideoEncoderConfig *cfg = self.videoEncoderConfig;
        NSString* codecName = cfg.rawCodecName; // i.e. @"libx264"
        if (!codecName.length) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot find video encoder name.");
            goto end;
        }
        
        codec = avcodec_find_encoder_by_name([codecName UTF8String]);
        if (!codec) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot find video encoder.");
            goto end;
        }
        
        avctx = avcodec_alloc_context3(codec);
        if (!avctx) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot allocate encoder context.");
            goto end;
        }
    }
    
    // Setup encoder paramters
    {
        // Setup encoder paramters using CMSampleBuffer or AVFrame/AVFilterContext
        if (sb) {
            int width = 0, height = 0;
            if (CMSBGetWidthHeight(sb, &width, &height) == FALSE) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate dimensions.");
                goto end;
            }
            
            AVRational timebase_q = av_make_q(1, time_base);
#if 0
            if (CMSBGetTimeBase(sb, &timebase_q) == FALSE) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate timebase.");
                goto end;
            }
#endif
            AVRational sample_aspect_ratio = av_make_q(1, 1);
            if (CMSBGetAspectRatio(sb, &sample_aspect_ratio) == FALSE) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate aspect ratio.");
                goto end;
            }
            
            //// WARNING: non-propagated into decoded 2vuy SampleBuffer ////
            int fieldCount = 1, top_field_first = 0;
            if (CMSBGetFieldInfo(sb, &fieldCount, &top_field_first) == FALSE) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate field info.");
                goto end;
            }
            
            int colorspace = 0;
            if (CMSBGetColorSPC(sb, &colorspace) == FALSE) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate color space.");
                goto end;
            }
            
            int color_range = 0;
            if (CMSBGetColorRange(sb, &color_range) == FALSE) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate color range.");
                goto end;
            }
            
            int color_trc = 0;
            if
#if 0
                (CMSBGetColorTRC(sb, &color_trc) == FALSE) // decoded SB
#else
                (CMSBGetColorTRC_FDE(sourceExtensions, &color_trc) == FALSE) // source SB
#endif
            {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate color trc.");
                goto end;
            }
            
            int color_primaries = 0;
            if
#if 0
                (CMSBGetColorPRI(sb, &color_primaries) == FALSE) // decoded SB
#else
                (CMSBGetColorPRI_FDE(sourceExtensions, &color_primaries) == FALSE) // source SB
#endif
            {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate color primaries.");
                goto end;
            }
            
            int chroma_location = 0;
            if (CMSBGetChromaLoc(sb, &chroma_location) == FALSE) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate chroma location.");
                goto end;
             }
            
            struct AVFPixelFormatSpec encodeFormat = {};
            if (CMSBGetPixelFormatSpec(sb, &encodeFormat)) {
                pxl_fmt_encode = encodeFormat;
            }

            // Use CMSampleBuffer parameter
            avctx->pix_fmt = pxl_fmt_encode.ff_id;
            avctx->width = width;
            avctx->height = height;
            avctx->time_base = timebase_q;
            avctx->sample_aspect_ratio = sample_aspect_ratio;
            avctx->field_order = AV_FIELD_PROGRESSIVE;
            if (fieldCount == 2) {
                if (top_field_first) {
                    avctx->field_order = AV_FIELD_TT;
                } else {
                    avctx->field_order = AV_FIELD_BB;
                }
            }
            avctx->colorspace = colorspace;
            avctx->color_range = color_range;
            avctx->color_trc = color_trc;
            avctx->color_primaries = color_primaries;
            avctx->chroma_sample_location = chroma_location;
        } else {
            // Use filtered frame and buffersink context
            if (!self.filteredValid) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot get source filtered video frame.");
                 goto end;
             }
            
            struct AVFPixelFormatSpec encodeFormat = {};
            if (AVFrameGetPixelFormatSpec(filtered, &encodeFormat)) {
                pxl_fmt_encode = encodeFormat;
            }
            
            avctx->pix_fmt = pxl_fmt_encode.ff_id;
            avctx->width = filtered->width;
            avctx->height = filtered->height;
            avctx->time_base = av_make_q(1, time_base);
            avctx->sample_aspect_ratio = filtered->sample_aspect_ratio;
            avctx->field_order = AV_FIELD_PROGRESSIVE;
            if (filtered->flags & AV_FRAME_FLAG_INTERLACED) {
                if (filtered->flags & AV_FRAME_FLAG_TOP_FIELD_FIRST) {
                    avctx->field_order = AV_FIELD_TT;
                } else {
                    avctx->field_order = AV_FIELD_BB;
                }
            }
            avctx->colorspace = filtered->colorspace;
            avctx->color_range = filtered->color_range;
            avctx->color_trc = filtered->color_trc;
            avctx->color_primaries = filtered->color_primaries;
            avctx->chroma_sample_location = filtered->chroma_location;
        }
        
        avctx->flags |= (AV_CODEC_FLAG_GLOBAL_HEADER | AV_CODEC_FLAG_CLOSED_GOP); // Use Closed GOP by default
        
        MEVideoEncoderConfig *cfg = self.videoEncoderConfig;
        if (cfg.hasFrameRate) {
            CMTime fraction = cfg.frameRate;
            if (!CMTIME_IS_VALID(fraction)) {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate fpsValue");
                 goto end;
            }
            // fps CMTime; e.g. 60000/2002 = 30000/1001 = 29.97fps
            int timebase = (int32_t)fraction.value;
            int duration = (int32_t)fraction.timescale;
            AVRational frameRate = av_make_q(timebase, duration);
            //
            avctx->framerate = frameRate;
            avctx->time_base = av_make_q(1, timebase);
        }
        
        // av_dict_set(&opts, "b", "2.5M", 0);
        MEVideoEncoderConfig *cfgBR = self.videoEncoderConfig;
        if (cfgBR.bitRate > 0) {
            avctx->bit_rate = cfgBR.bitRate;
        }
    }
    
    {
        NSDictionary* setting = [self.videoEncoderSetting copy];
        if (setting) {
            NSValue *rawSizeValue = setting[kMEVECodecWxHKey];
            NSValue *aspectValue = setting[kMEVECodecPARKey];
            if (rawSizeValue) {
                NSSize rawSize = [rawSizeValue sizeValue];
                BOOL hDiff = (avctx->width != rawSize.width);
                BOOL vDiff = (avctx->height != rawSize.height);
                if (hDiff || vDiff) {
                    SecureLogf(@"[MEManager] Ignroing -meve \"size=%d:%d\"",
                               (int)rawSize.width, (int)rawSize.height);
                }
            }
            if (aspectValue) {
                NSSize aspect = [aspectValue sizeValue];
                BOOL hDiff = (avctx->sample_aspect_ratio.num != aspect.width);
                BOOL vDiff = (avctx->sample_aspect_ratio.den != aspect.height);
                if (hDiff || vDiff) {
                    SecureLogf(@"[MEManager] Ignroing -meve \"par=%d:%d\"",
                               (int)aspect.width, (int)aspect.height);
                }
            }
        }
    }

    // Setup encoder options
    {
#if 0
        // TODO: this will work as "crop", not "overscan"
        // clean aperture information as vui parameters
        NSValue *cleanApertureValue = self.videoEncoderConfig.cleanAperture ?: videoEncoderSetting[kMEVECodecCleanAperture];
        if (cleanApertureValue) {
            NSRect rect = [cleanApertureValue rectValue];
            int left = (avctx->width - rect.origin.x + rect.size.width) / 2;
            int top = (avctx->height - rect.origin.y + rect.size.height) / 2;
            int right = (avctx->width - rect.origin.x  - rect.size.width) / 2;
            int bottom = (avctx->height - rect.origin.y - rect.size.height) / 2;
            
            if (uselibx264(self)) {
                @autoreleasepool {
                    NSString *cropParam = [NSString stringWithFormat:@"overscan=crop:crop-rect=%d,%d,%d,%d", left,top,right,bottom];
                    NSString* x264_params = videoEncoderSetting[kMEVEx264_paramsKey];
                    if (x264_params) {
                        NSString *newParams = [cropParam stringByAppendingFormat:@":%@", x264_params];
                        videoEncoderSetting[kMEVEx264_paramsKey] = newParams;
                    } else {
                        videoEncoderSetting[kMEVEx264_paramsKey] = cropParam;
                    }
                }
            }
            if (uselibx265(self)) {
                @autoreleasepool {
                    NSString *cropParam = [NSString stringWithFormat:@"display-window=%d,%d,%d,%d", left,top,right,bottom];
                    NSString* x265_params = videoEncoderSetting[kMEVEx265_paramsKey];
                    if (x265_params) {
                        NSString *newParams = [cropParam stringByAppendingFormat:@":%@", x265_params];
                        videoEncoderSetting[kMEVEx265_paramsKey] = newParams;
                    } else {
                        videoEncoderSetting[kMEVEx265_paramsKey] = cropParam;
                    }
                }
            }
        }
#endif

        // av_dict_set( &codec_options, "AnyCodecParameter", "Value", 0 );
        /*
         Example libx264:
         CRF:"preset=medium:profile=high:level=4.1:maxrate=15M:bufsize=15M:crf=23:g=60:keyint_min=15:bf=3"
         ABR:"preset=medium:profile=high:level=4.1:maxrate=15M:bufsize=15M:b=2.5M:g=60:keyint_min=15:bf=3"
         */
        NSDictionary* codecOptions = self.videoEncoderConfig.codecOptions;
        if (codecOptions) {
            @autoreleasepool {
                for (NSString* key in codecOptions.allKeys) {
                    NSString* value = codecOptions[key];
                    
                    const char* _key = [key UTF8String];
                    const char* _value = [value UTF8String];
                    ret = av_dict_set(&opts, _key, _value, 0);
                    if (ret < 0) {
                        SecureErrorLogf(@"[MEManager] ERROR: Cannot update codecOptions.");
                        goto end;
                    }
                }
            }
        }
        
        // encoder specific options
        /*
         Example libx264
         CRF:"preset=medium:profile=high:level=4.1:vbv-maxrate=15000:vbv-bufsize=15000:crf=23:keyint=60:min-keyint=6:bframes=3"
         AVR:"preset=medium:profile=high:level=4.1:vbv-maxrate=15000:vbv-bufsize=15000:bitrate=2500:keyint=60:min-keyint=6:bframes=3"
         */
        if (uselibx264(self)) {
            NSString* params = self.videoEncoderConfig.x264Params;
            if (params) {
                ret = av_dict_set(&opts, "x264-params", [params UTF8String], 0);
                if (ret < 0) {
                    SecureErrorLogf(@"[MEManager] ERROR: Cannot update x264-params.");
                    goto end;
                }
            }
        }
        if (uselibx265(self)) {
            NSString* params = self.videoEncoderConfig.x265Params;
            if (params) {
                ret = av_dict_set(&opts, "x265-params", [params UTF8String], 0);
                if (ret < 0) {
                    SecureErrorLogf(@"[MEManager] ERROR: Cannot update x265-params.");
                    goto end;
                }
            }
        }
    }
    
    char* buf;
    ret = av_dict_get_string(opts, &buf, '=', ':');
    if (ret == 0 && buf != NULL) {
        @autoreleasepool {
            NSString* codecOptString = [NSString stringWithUTF8String:buf];
            av_freep(&buf);
            
            if (self.verbose) {
                SecureDebugLogf(@"[MEManager] codecOptString = %@", codecOptString);
            }
         }
    }
    
    // Initialize encoder
    SecureLogf(@"");
    ret = avcodec_open2(avctx, codec, &opts);
    if (ret < 0) {
        SecureErrorLogf(@"[MEManager] ERROR: Cannot open video encoder.");
        goto end;
    }
    SecureLogf(@"");

    self.videoEncoderIsReady = TRUE;
    
    // Signal that encoder is ready
    dispatch_semaphore_signal(self.encoderReadySemaphore);
    
end:
    av_dict_free(&opts);
    
    return self.videoEncoderIsReady;
}

/**
 Setup VideoFilter using parameters from CMSampleBuffer

 @param sb CMSampleBuffer
 @return TRUE if success. FALSE if fail.
 */
- (BOOL)prepareVideoFilterWith:(CMSampleBufferRef)sb
{
    char *filters_descr = NULL;
    AVFilterInOut *outputs = NULL;
    AVFilterInOut *inputs  = NULL;
    char args[512] = {0};

    if (self.videoFilterIsReady) {
        return TRUE;
    }
    if (!(videoFilterString && videoFilterString.length)) {
        SecureErrorLogf(@"[MEManager] ERROR: Invalid video filter parameters.");
        goto end;
    }
    if (sb == NULL) {
        SecureErrorLogf(@"[MEManager] ERROR: Invalid video filter parameters.");
        goto end;
    }
    
    // Validate source CMSampleBuffer
    {
        int width = 0, height = 0;
        if (CMSBGetWidthHeight(sb, &width, &height) == FALSE) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot validate dimensions.");
            goto end;
        }
        AVRational sample_aspect_ratio = av_make_q(1, 1);
        if (CMSBGetAspectRatio(sb, &sample_aspect_ratio) == FALSE) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot validate aspect ratio.");
            goto end;
        }
        
        pxl_fmt_filter = AVFPixelFormatSpecNone;
        if (!(CMSBGetPixelFormatSpec(sb, &pxl_fmt_filter) && pxl_fmt_filter.avf_id != 0)) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot validate pixel_format.");
            goto end;
        }
        
        AVRational timebase_q = av_make_q(1, time_base);
        if (time_base == 0) { // fallback
            if (CMSBGetTimeBase(sb, &timebase_q)) {
                time_base = timebase_q.den;
            } else {
                SecureErrorLogf(@"[MEManager] ERROR: Cannot validate timebase.");
                goto end;
            }
        }
        
        snprintf(args, sizeof(args),
                 "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
                 width, height, pxl_fmt_filter.ff_id,
                 timebase_q.num, timebase_q.den,
                 sample_aspect_ratio.num, sample_aspect_ratio.den);
        
        if (self.verbose) {
            SecureDebugLogf(@"[MEManager] avfilter.buffer = %@", [NSString stringWithUTF8String:args]);
        }
    }
    
    // Update log_level
    av_log_set_level(self.log_level);
    
    // Initialize AVFilter
    {
        int ret = AVERROR_UNKNOWN;
        filter_graph = avfilter_graph_alloc();
        
        /* buffer video source: the decoded frames from the decoder will be inserted here. */
        const AVFilter *buffersrc  = avfilter_get_by_name("buffer");
        ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in",
                                           args, NULL, filter_graph);
        if (ret < 0) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot create buffer source");
            goto end;
        }
        
        /* buffer video sink: to terminate the filter chain. */
        const AVFilter *buffersink = avfilter_get_by_name("buffersink");
        buffersink_ctx = avfilter_graph_alloc_filter(filter_graph, buffersink, "out");
        if (!buffersink_ctx) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot create buffer sink");
            goto end;
        }
        
        // Old approach (deprecated in FFmpeg 8.0+): av_opt_set_int_list was used to set pixel formats.
        // This API is now deprecated and may cause issues with newer FFmpeg versions.
        // The current recommended approach is to use av_opt_set_bin (see below).
        size_t pix_fmts_length = 0;
        for (size_t i = 0; pix_fmt_list[i] != AV_PIX_FMT_NONE; i++) {
            pix_fmts_length++;
        }
        size_t size_bytes = pix_fmts_length * sizeof(enum AVPixelFormat);
        ret = av_opt_set_bin(buffersink_ctx, "pix_fmts",
                             (uint8_t *)pix_fmt_list,
                             (int)size_bytes,
                             AV_OPT_SEARCH_CHILDREN);
        if (ret < 0) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot set output pixel format");
            goto end;
        }
        
        ret = avfilter_init_str(buffersink_ctx, NULL);
        if (ret < 0) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot initialize buffer sink");
            goto end;
        }
        
        /*
         * Set the endpoints for the filter graph. The filter_graph will
         * be linked to the graph described by filters_descr.
         */
        
        /*
         * The buffer source output must be connected to the input pad of
         * the first filter described by filters_descr; since the first
         * filter input label is not specified, it is set to "in" by
         * default.
         */
        outputs = avfilter_inout_alloc();
        outputs->name       = av_strdup("in");
        outputs->filter_ctx = buffersrc_ctx;
        outputs->pad_idx    = 0;
        outputs->next       = NULL;
        
        /*
         * The buffer sink input must be connected to the output pad of
         * the last filter described by filters_descr; since the last
         * filter output label is not specified, it is set to "out" by
         * default.
         */
        inputs  = avfilter_inout_alloc();
        inputs->name       = av_strdup("out");
        inputs->filter_ctx = buffersink_ctx;
        inputs->pad_idx    = 0;
        inputs->next       = NULL;
        
        filters_descr = av_strdup([videoFilterString UTF8String]);
        if ((ret = avfilter_graph_parse_ptr(filter_graph, filters_descr,
                                            &inputs, &outputs, NULL)) < 0) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot parse filter descriptions. (%d)", ret);
            goto end;
        }
        
        if ((ret = avfilter_graph_config(filter_graph, NULL)) < 0) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot configure filter graph. (%d)", ret);
            goto end;
        }
    }
    self.videoFilterIsReady = TRUE;
    
    // Signal that filter is ready
    dispatch_semaphore_signal(self.filterReadySemaphore);
    
    if (self.verbose) {
        char* dump = avfilter_graph_dump(filter_graph, NULL);
        if (dump) {
            SecureDebugLogf(@"[MEManager] avfilter_graph_dump() returned %lu bytes.", (unsigned long)strlen(dump));
            av_log(NULL, AV_LOG_INFO, "%s\n", dump);
        }
        av_free(dump);
    }
    
end:
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    av_free(filters_descr);
    
    return self.videoFilterIsReady;
}

/**
 Prepare input AVFrame from CMSampleBuffer and it's CVImageBuffer

 @param sb CMSampleBuffer
 @return TRUE if success. FALSE if fail.
 */
- (BOOL)prepareInputFrameWith:(CMSampleBufferRef)sb
{
    // get input stream timebase
    if (time_base == 0) { // fallbak
        AVRational timebase_q = {1, 1};
        if (CMSBGetTimeBase(sb, &timebase_q)) {
            time_base = timebase_q.den;
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
        
        av_frame_unref(input);
        AVFrameReset(input);
        
        input->format = pxl_fmt_filter.ff_id;
        input->width = width;
        input->height = height;
        input->time_base = av_make_q(1,time_base);
        
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
        result = CMSBCopyParametersToAVFrame(sb, input, time_base);
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
        if (!colorMetadataCached) {
            cachedColorMetadata.color_range = input->color_range;
            cachedColorMetadata.color_primaries = input->color_primaries;
            cachedColorMetadata.color_trc = input->color_trc;
            cachedColorMetadata.colorspace = input->colorspace;
            cachedColorMetadata.chroma_location = input->chroma_location;
            colorMetadataCached = TRUE;
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
    // From AVFrame to CMSampleBuffer(CVImageBuffer); Uncompressed
    CVPixelBufferRef pb = NULL;
    CMSampleBufferRef sb = NULL;
    OSStatus err = noErr;

    if (!useVideoFilter(self)) {
        SecureErrorLogf(@"[MEManager] ERROR: Invalid state detected.");
        goto end;
    }
    
    // Create PixelBufferPool for unompressed AVFrame
    if (filtered && !cvpbpool) {
        cvpbpool = AVFrameCreateCVPixelBufferPool(filtered);
        if (!cvpbpool) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup CVPixelBufferPool.");
            goto end;
        }
    }
    
    // Create PixelBuffer Attachments dictionary
    if (filtered && !pbAttachments) {
        pbAttachments = AVFrameCreateCVBufferAttachments(filtered);
        if (!pbAttachments) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup CVBufferAttachments.");
            goto end;
        }
    }
    
    // Create new PixelBuffer for uncompressed AVFrame
    if (filtered && cvpbpool) {
        pb = AVFrameCreateCVPixelBuffer(filtered, cvpbpool);
        if (!pb) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup CVPixelBuffer.");
            goto end;
        }
    }
    
    // Fill PixelBuffer attachments using properties of filtered AVFrame
    if (pb && pbAttachments) {
        CVBufferSetAttachments(pb, pbAttachments, kCVAttachmentMode_ShouldPropagate);
    }
    
    // Create formatDescription for PixelBuffer
    if (pb && !desc) {
        CMVideoFormatDescriptionRef descForPB = NULL;
        err = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,
                                                           pb,
                                                           &descForPB);
        if (err || !descForPB) {
            goto end;
        }
        desc = descForPB;
    }
    
    if (pb && desc && time_base) {
        CMSampleBufferRef sbForPB = NULL;
        CMSampleTimingInfo info = {
            kCMTimeInvalid,
            CMTimeMake(filtered->pts, time_base),
            CMTimeMake(filtered->pkt_dts, time_base)
        };
        err = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                       pb,
                                                       desc,
                                                       &info,
                                                       &sbForPB);
        if (err || !sbForPB) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup uncompressed CMSampleBuffer.");
            goto end;
        }
        sb = sbForPB;
        
        CVPixelBufferRelease(pb);
        return sb;
    }
    
end:
    if (pb) {
        CVPixelBufferRelease(pb);
    }
    return NULL;
}

/**
 Create CMSampleBuffer using output from VideoEncoder

 @return CMSampleBuffer
 */
-(nullable CMSampleBufferRef)createCompressedSampleBuffer
{
    if (!useVideoEncoder(self)) {
        SecureErrorLogf(@"[MEManager] ERROR: Invalid state detected.");
        goto end;
    }
    
    if (!desc) {
        if (uselibx264(self)) {
            desc = createDescriptionH264(avctx);
        } else
        if (uselibx265(self)) {
            desc = createDescriptionH265(avctx);
        }
        if (!desc) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup CMVideoFormatDescription.");
            goto end;
        }
        
        // Append container level clean aperture
        NSValue *cleanApertureValue = self.videoEncoderConfig.cleanAperture ?: videoEncoderSetting[kMEVECleanApertureKey];
        if (cleanApertureValue) {
            desc = createDescriptionWithAperture(desc, cleanApertureValue);
        }
        if (!desc) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup CMVideoFormatDescription with clean apreture.");
            goto end;
        }
    }
    
    // From AVPacket to CMSampleBuffer(CMBLockBuffer); Compressed
    if (desc && time_base) {
        // Get temp NAL buffer
        int tempSize = encoded->size;
        UInt8* tempPtr = av_malloc(tempSize);
        if (!tempPtr) {
            SecureErrorLogf(@"[MEManager] ERROR: Failed to allocate %d bytes for NAL processing", tempSize);
            goto end;
        }
        
        // Re-format NAL unit with bounds checking
        if (tempSize > 0 && encoded->data) {
            memcpy(tempPtr, encoded->data, tempSize);
            avc_parse_nal_units(&tempPtr, &tempSize);    // This call frees original buffer and allocates new one
        } else {
            SecureErrorLogf(@"[MEManager] ERROR: Invalid data for NAL processing: tempSize=%d, encoded->data=%p",
                  tempSize, encoded->data);
            av_free(tempPtr);
            goto end;
        }
        
        // Create CMBlockBuffer
        OSStatus err = noErr;
        CMBlockBufferRef bb = NULL;
        err = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,   // allocator of CMBlockBuffer
                                                 NULL,                  // allocate new memoryBlock
                                                 tempSize,              // requested size of memoryBlock
                                                 kCFAllocatorDefault,   // allocator of memoryBlock
                                                 NULL,                  // No custom block source
                                                 0,                     // offset to data in memoryBlock
                                                 tempSize,              // length of data in memoryBlock
                                                 kCMBlockBufferAssureMemoryNowFlag,
                                                 &bb);
        if (err) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup CMBlockBuffer.");
            av_free(tempPtr);
            goto end;
        }
        
        // Copy NAL buffer into CMBlockBuffer
        err = CMBlockBufferReplaceDataBytes(tempPtr,                    // Data source pointer
                                            bb,                         // target CMBlockBuffer
                                            0,                          // replacing offset of target memoryBlock
                                            tempSize);                  // replacing size of data written from offset
        av_free(tempPtr);
        if (err) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup CMBlockBuffer.");
            if (bb) CFRelease(bb);
            goto end;
        }
        
        // Create CMSampleBuffer from CMBlockBuffer
        CMItemCount numSamples = 1;
        CMSampleTimingInfo info = {
            kCMTimeInvalid,
            CMTimeMake(encoded->pts, time_base),
            CMTimeMake(encoded->dts, time_base)
        };
        CMSampleTimingInfo sampleTimingArray[1] = { info };
        CMItemCount numSampleTimingEntries = 1;
        size_t sampleSizeArray[1] = { tempSize };
        CMItemCount numSampleSizeEntries = 1;
        CMSampleBufferRef sb = NULL;
        err = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                        bb,
                                        desc,
                                        numSamples,
                                        numSampleTimingEntries,
                                        sampleTimingArray,
                                        numSampleSizeEntries,
                                        sampleSizeArray,
                                        &sb);
        if (bb) CFRelease(bb);
        if (err) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot setup compressed CMSampleBuffer.");
            goto end;
        }
        
        // get AV_PICTURE_TYPE_xxx
        size_t side_size = 0;
        uint8_t *side = av_packet_get_side_data(self->encoded,
                                                AV_PKT_DATA_QUALITY_STATS,
                                                &side_size);
        if (side && side_size >= 5) {
            int picture_type = (int)side[4];
            char typeChar = av_get_picture_type_char(picture_type);
            enum AVCodecID cid = self->avctx ? self->avctx->codec_id : AV_CODEC_ID_NONE;
            BOOL isKey = (self->encoded->flags & AV_PKT_FLAG_KEY) != 0;
#if 0
            NSString* isKeyStr = isKey ? @"KEY" : @"";
            SecureDebugLogf(@"[MEManager] picType=%c codec=%d %@", typeChar, (int)cid, isKeyStr);
#endif
            CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sb, YES);
            CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            CFDictionaryAddValue(dict, kCMSampleAttachmentKey_EarlierDisplayTimesAllowed, kCFBooleanTrue);
            
            if (cid == AV_CODEC_ID_H264) {
                // H.264 specific refinement using NAL header (first NAL after 4-byte length)
                if (encoded->size >= 5) {
                    const uint8_t firstNalHdr = encoded->data[4];
                    int nal_ref_idc = (0x60 & firstNalHdr) >> 5;
                    int nal_unit_type = (0x1f & firstNalHdr);
                    if (typeChar == 'I') {
                        if (nal_unit_type == 5) { // IDR
                            CFDictionaryAddValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanFalse);
                        } else {
                            // Non-IDR I (partial sync)
                            CFDictionaryAddValue(dict, kCMSampleAttachmentKey_PartialSync, kCFBooleanTrue);
                            CFDictionaryAddValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
                            CFBooleanRef required = (nal_ref_idc != 0x00) ? kCFBooleanTrue : kCFBooleanFalse;
                            CFDictionaryAddValue(dict, kCMSampleAttachmentKey_IsDependedOnByOthers, required);
                        }
                        return sb;
                    }
                    if (typeChar == 'P') {
                        CFDictionaryAddValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
                        CFDictionaryAddValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanTrue);
                        return sb;
                    }
                    if (typeChar == 'B') {
                        CFDictionaryAddValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
                        CFDictionaryAddValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanTrue);
                        CFBooleanRef required = (nal_ref_idc != 0x00) ? kCFBooleanTrue : kCFBooleanFalse;
                        CFDictionaryAddValue(dict, kCMSampleAttachmentKey_IsDependedOnByOthers, required);
                        return sb;
                    }
                }
                // Fall through to generic behavior if header unavailable
            }
            
            // Generic and HEVC behavior
            if (typeChar == 'I') {
                if (isKey) {
                    // Treat as sync sample
                    CFDictionaryAddValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanFalse);
                } else {
                    // Open-GOP non-IDR I or CRA-like frames without full random access
                    CFDictionaryAddValue(dict, kCMSampleAttachmentKey_PartialSync, kCFBooleanTrue);
                    CFDictionaryAddValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
                }
                return sb;
            }
            if (typeChar == 'P' || typeChar == 'B') {
                CFDictionaryAddValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
                CFDictionaryAddValue(dict, kCMSampleAttachmentKey_DependsOnOthers, kCFBooleanTrue);
                return sb;
            }
        }
    }
    
end:
    return NULL;
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
        if (inputFrameIsReady) {
            *ret = av_buffersrc_add_frame(self->buffersrc_ctx, self->input);
        } else {
            *ret = av_buffersrc_add_frame(self->buffersrc_ctx, NULL);
        }
        if (*ret == 0) {
            if (inputFrameIsReady) {
                av_frame_unref(self->input);
                self.lastEnqueuedPTS = newPTS;
                // Signal timestamp gap semaphore when PTS is updated
                dispatch_semaphore_signal(self.timestampGapSemaphore);
#if 0
                float pts0 = (float)self->_lastEnqueuedPTS/self->time_base;
                float pts1 = (float)self->_lastDequeuedPTS/self->time_base;
                float diff = fabsf(pts1-pts0);
                SecureDebugLogf(@"[Filter] enqueued:%8.2f, dequeued:%8.2f, diffInSec:%5.2f", pts0, pts1, diff );
#endif
            } else {
                self.videoFilterFlushed = TRUE;
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
        if (inputFrameIsReady) {
            *ret = avcodec_send_frame(self->avctx, self->input);
        } else {
            *ret = avcodec_send_frame(self->avctx, NULL);
        }
        if (*ret == 0) {
            if (inputFrameIsReady) {
                av_frame_unref(self->input);
            } else {
                self.videoEncoderFlushed = TRUE;
            }
            self.writerStatus = AVAssetWriterStatusWriting;
            return;
        } else {
            if (*ret == AVERROR(EAGAIN)) {
                return;
            } else if (*ret == AVERROR_EOF) {
                return;
            } else {
                SecureErrorLogf(@"[MEManager] ERROR: avcodec_send_frame() returned %08X", *ret);
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
        int64_t gapLimitInSec = self->time_base * 10;
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
    return time_base;
}

- (void)setMediaTimeScale:(CMTimeScale)mediaTimeScale
{
    time_base = mediaTimeScale;
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
    if (self.videoFilterEOF) return;
    if (!self->filtered) {                                  // Prepare filtered frame
        self.filteredValid = FALSE;
        self->filtered = av_frame_alloc();                  // allocate frame
        if (!self->filtered) {
            SecureErrorLogf(@"[MEManager] ERROR: Failed to allocate a video frame.");
            goto error;
        }
    }
    
    if (!self.videoFilterIsReady) {
        *ret = AVERROR_UNKNOWN;
        SecureErrorLogf(@"[MEManager] ERROR: the filtergraph is not ready.");
        goto error;
    }
    if (self.filteredValid) {
        *ret = 0;
        return;
    }

    // Update filtered with filter graph output
    *ret = av_buffersink_get_frame(self->buffersink_ctx, self->filtered);
    if (*ret == 0) {
        self.filteredValid = TRUE;                          // filtered is now ready
        
        AVFilterLink *input = (self->buffersink_ctx->inputs)[0];
        AVRational filtered_time_base = input->time_base;
        AVRational bq = filtered_time_base;
        AVRational cq = av_make_q(1, self->time_base);
        int64_t newpts = av_rescale_q(self->filtered->pts, bq, cq);
        self->filtered->pts = newpts;
        self.lastDequeuedPTS = newpts;
        // Signal timestamp gap semaphore when PTS is updated
        dispatch_semaphore_signal(self.timestampGapSemaphore);
        return;
    } else if (*ret == AVERROR(EAGAIN)) {                   // Needs more frame to graph
        return;
    } else if (*ret == AVERROR_EOF) {                       // Filter has completed its job
        self.videoFilterEOF = TRUE;
        return;
    } else {
        SecureErrorLogf(@"[MEManager] ERROR: Failed to av_buffersink_get_frame() (%d)", *ret);
    }

error:
    self.failed = TRUE;
    self.writerStatus = AVAssetWriterStatusFailed;
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
        *ret = avcodec_send_frame(self->avctx, self->filtered);
        if (*ret == 0) {
            av_frame_unref(self->filtered);
            self.filteredValid = FALSE;
            return;
        } else if (*ret == AVERROR(EAGAIN)) {               // encoder is busy - Try again later
            return;
        } else if (*ret == AVERROR_EOF) {
            //self.writerStatus = AVAssetWriterStatusCompleted;
            return;
        } else {
            SecureErrorLogf(@"[MEManager] ERROR: failed to avcodec_send_frame().");
        }
    } else if (self.videoFilterEOF) {                       // Push flush frame into encoder
        *ret = avcodec_send_frame(self->avctx, NULL);
        if (*ret == 0) {
            self.videoEncoderFlushed = TRUE;
            return;
        } else if (*ret == AVERROR(EAGAIN)) {               // encoder is busy - Try again later
            return;
        } else if (*ret == AVERROR_EOF) {
            //self.writerStatus = AVAssetWriterStatusCompleted;
            return;
        } else {
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
    
    if (!self->encoded) {                                   // Prepare encoded packet
        self->encoded = av_packet_alloc();
        if (!self->encoded) {
            SecureErrorLogf(@"[MEManager] ERROR: Failed to allocate a video packet.");
            goto error;
        }
    }
    
    if (!self.videoEncoderIsReady) {
        *ret = AVERROR_UNKNOWN;
        SecureErrorLogf(@"[MEManager] ERROR: the encoder is not ready.");
        goto error;
    }
    
    // Update encoded with encoder output
    *ret = avcodec_receive_packet(self->avctx, self->encoded);
    if (*ret == 0) {
        return;
    } else if (*ret == AVERROR(EAGAIN)) {                   // Encoder requests more input
        return;
    } else if (*ret == AVERROR_EOF) {                       // Fully flushed out
        self.videoEncoderEOF = TRUE;
        self.readerStatus = AVAssetReaderStatusCompleted;
        return;
    } else {
        SecureErrorLogf(@"[MEManager] ERROR: Failed to avcodec_receive_packet().");
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
                    if (!videoFilterEOF) {
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
                        if (self.filteredValid && self->filtered && self->colorMetadataCached) {
                            AVFrameFillMetadataFromCache(self->filtered, &self->cachedColorMetadata);
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
                av_packet_unref(encoded);
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
                self.filteredValid = FALSE;
                av_frame_unref(filtered);
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
