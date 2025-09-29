//
//  MEEncoderPipeline.m
//  movencoder2
//
//  Created by Copilot on 2025-09-29.
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

#import "MEEncoderPipeline.h"
#import "MECommon.h"
#import "MEUtils.h"
#import "MESecureLogging.h"
#import "MEErrorFormatter.h"
#import "Config/MEVideoEncoderConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface MEEncoderPipeline ()
{
    struct AVFPixelFormatSpec pxl_fmt_encode;
    AVCodecContext *avctx;
    AVPacket *encoded;
}

@property (atomic, readwrite) BOOL isReady;
@property (atomic, readwrite) BOOL isEOF;
@property (atomic, readwrite) BOOL isFlushed;
@property (atomic, strong, readwrite, nullable) MEVideoEncoderConfig *videoEncoderConfig;
@property (atomic, assign) BOOL configIssuesLogged;

@end

NS_ASSUME_NONNULL_END

@implementation MEEncoderPipeline

@synthesize encoderReadySemaphore = _encoderReadySemaphore;

// Utility functions for encoder pipeline
static inline BOOL useVideoEncoder(MEEncoderPipeline *obj) {
    return (obj.videoEncoderSetting != NULL);
}

static inline BOOL uselibx264(MEEncoderPipeline *obj) {
    if (!useVideoEncoder(obj)) return NO;
    MEVideoEncoderConfig *cfg = obj.videoEncoderConfig;
    return (cfg && cfg.codecKind == MEVideoCodecKindX264);
}

static inline BOOL uselibx265(MEEncoderPipeline *obj) {
    if (!useVideoEncoder(obj)) return NO;
    MEVideoEncoderConfig *cfg = obj.videoEncoderConfig;
    return (cfg && cfg.codecKind == MEVideoCodecKindX265);
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _encoderReadySemaphore = dispatch_semaphore_create(0);
        
        pxl_fmt_encode = AVFPixelFormatSpecNone;
        avctx = NULL;
        encoded = NULL;
        
        _isReady = NO;
        _isEOF = NO;
        _isFlushed = NO;
        _verbose = NO;
        _logLevel = AV_LOG_ERROR;
        _timeBase = 0;
        _configIssuesLogged = NO;
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    av_packet_free(&encoded);
    avcodec_free_context(&avctx);
    
    self.isReady = NO;
    self.isEOF = NO;
    self.isFlushed = NO;
    
    // Note: Don't release sourceExtensions here as it might be shared
}

- (MEVideoEncoderConfig * _Nullable)videoEncoderConfig
{
    @synchronized(self) {
        if (!_videoEncoderConfig && self.videoEncoderSetting) {
            _videoEncoderConfig = [[MEVideoEncoderConfig alloc] initWithSettings:self.videoEncoderSetting];
        }
        return _videoEncoderConfig;
    }
}

- (void)setVideoEncoderConfig:(MEVideoEncoderConfig * _Nullable)config
{
    @synchronized(self) {
        _videoEncoderConfig = config;
    }
}

- (BOOL)prepareVideoEncoderWith:(CMSampleBufferRef _Nullable)sampleBuffer 
                  filteredFrame:(void * _Nullable)filteredFrame
            hasValidFilteredFrame:(BOOL)hasValidFilteredFrame
{
    int ret = 0;
    const AVCodec* codec = NULL;
    AVDictionary* opts = NULL;
    MEVideoEncoderConfig *cfgLog = nil;
    
    if (self.isReady)
        return YES;
    if (!(self.videoEncoderSetting && self.videoEncoderSetting.count)) {
        SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Invalid video encoder parameters.");
        goto end;
    }
    
    // Update log_level
    av_log_set_level(self.logLevel);
    
    // Allocate encoder context
    {
        MEVideoEncoderConfig *cfg = self.videoEncoderConfig;
        NSString* codecName = cfg.rawCodecName; // i.e. @"libx264"
        if (!codecName.length) {
            SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot find video encoder name.");
            goto end;
        }
        
        codec = avcodec_find_encoder_by_name([codecName UTF8String]);
        if (!codec) {
            SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot find video encoder.");
            goto end;
        }
        
        avctx = avcodec_alloc_context3(codec);
        if (!avctx) {
            SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot allocate encoder context.");
            goto end;
        }
    }
    
    // Setup encoder parameters
    {
        // Setup encoder parameters using CMSampleBuffer or AVFrame/AVFilterContext
        if (sampleBuffer) {
            int width = 0, height = 0;
            if (CMSBGetWidthHeight(sampleBuffer, &width, &height) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate dimensions.");
                goto end;
            }
            
            AVRational timebase_q = av_make_q(1, self.timeBase);
            AVRational sample_aspect_ratio = av_make_q(1, 1);
            if (CMSBGetAspectRatio(sampleBuffer, &sample_aspect_ratio) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate aspect ratio.");
                goto end;
            }
            
            //// WARNING: non-propagated into decoded 2vuy SampleBuffer ////
            int fieldCount = 1, top_field_first = 0;
            if (CMSBGetFieldInfo(sampleBuffer, &fieldCount, &top_field_first) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate field info.");
                goto end;
            }
            
            int colorspace = 0;
            if (CMSBGetColorSPC(sampleBuffer, &colorspace) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate color space.");
                goto end;
            }
            
            int color_range = 0;
            if (CMSBGetColorRange(sampleBuffer, &color_range) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate color range.");
                goto end;
            }
            
            int color_trc = 0;
            if (CMSBGetColorTRC_FDE(self.sourceExtensions, &color_trc) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate color trc.");
                goto end;
            }
            
            int color_primaries = 0;
            if (CMSBGetColorPRI_FDE(self.sourceExtensions, &color_primaries) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate color primaries.");
                goto end;
            }
            
            int chroma_location = 0;
            if (CMSBGetChromaLoc(sampleBuffer, &chroma_location) == FALSE) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate chroma location.");
                goto end;
            }
            
            struct AVFPixelFormatSpec encodeFormat = {};
            if (CMSBGetPixelFormatSpec(sampleBuffer, &encodeFormat)) {
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
            if (!hasValidFilteredFrame) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot get source filtered video frame.");
                 goto end;
             }
            
            AVFrame *frame = (AVFrame *)filteredFrame;
            struct AVFPixelFormatSpec encodeFormat = {};
            if (AVFrameGetPixelFormatSpec(frame, &encodeFormat)) {
                pxl_fmt_encode = encodeFormat;
            }
            
            avctx->pix_fmt = pxl_fmt_encode.ff_id;
            avctx->width = frame->width;
            avctx->height = frame->height;
            avctx->time_base = av_make_q(1, self.timeBase);
            avctx->sample_aspect_ratio = frame->sample_aspect_ratio;
            avctx->field_order = AV_FIELD_PROGRESSIVE;
            if (frame->flags & AV_FRAME_FLAG_INTERLACED) {
                if (frame->flags & AV_FRAME_FLAG_TOP_FIELD_FIRST) {
                    avctx->field_order = AV_FIELD_TT;
                } else {
                    avctx->field_order = AV_FIELD_BB;
                }
            }
            avctx->colorspace = frame->colorspace;
            avctx->color_range = frame->color_range;
            avctx->color_trc = frame->color_trc;
            avctx->color_primaries = frame->color_primaries;
            avctx->chroma_sample_location = frame->chroma_location;
        }
        
        avctx->flags |= (AV_CODEC_FLAG_GLOBAL_HEADER | AV_CODEC_FLAG_CLOSED_GOP); // Use Closed GOP by default
        
        MEVideoEncoderConfig *cfg = self.videoEncoderConfig;
        if (cfg.hasFrameRate) {
            CMTime fraction = cfg.frameRate;
            if (!CMTIME_IS_VALID(fraction)) {
                SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot validate fpsValue");
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
    
    // Setup encoder options
    {
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
                        SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot update codecOptions.");
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
                    SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot update x264-params.");
                    goto end;
                }
            }
        }
        if (uselibx265(self)) {
            NSString* params = self.videoEncoderConfig.x265Params;
            if (params) {
                ret = av_dict_set(&opts, "x265-params", [params UTF8String], 0);
                if (ret < 0) {
                    SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot update x265-params.");
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
                SecureDebugLogf(@"[MEEncoderPipeline] codecOptString = %@", codecOptString);
            }
         }
    }
    
    // Initialize encoder
    SecureLogf(@"");
    // Log any soft validation issues (verbose only)
    cfgLog = self.videoEncoderConfig;
    if (self.verbose && cfgLog.issues.count) {
        for (NSString *msg in cfgLog.issues) {
            SecureDebugLogf(@"[MEEncoderPipeline][ConfigIssue] %@", msg);
        }
    }
    ret = avcodec_open2(avctx, codec, &opts);
    if (ret < 0) {
        NSString *fferr = [MEErrorFormatter stringFromFFmpegCode:ret];
        SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Cannot open video encoder. %@", fferr);
        goto end;
    }
    SecureLogf(@"");

    self.isReady = YES;
    
    // Signal that encoder is ready
    dispatch_semaphore_signal(self.encoderReadySemaphore);
    
end:
    av_dict_free(&opts);
    
    return self.isReady;
}

- (BOOL)sendFrameToEncoder:(void *)frame withResult:(int *)result
{
    if (!self.isReady) {
        if (result) *result = AVERROR_UNKNOWN;
        return NO;
    }
    
    int ret;
    if (frame) {
        ret = avcodec_send_frame(avctx, (AVFrame *)frame);
        if (frame) {
            av_frame_unref((AVFrame *)frame);
        }
    } else {
        ret = avcodec_send_frame(avctx, NULL); // Flush
        self.isFlushed = YES;
    }
    
    if (result) *result = ret;
    
    if (ret == 0) {
        return YES;
    } else if (ret == AVERROR(EAGAIN)) {
        return YES; // Not an error, just needs more space
    } else if (ret == AVERROR_EOF) {
        return YES; // EOF is a valid state
    } else {
        SecureErrorLogf(@"[MEEncoderPipeline] ERROR: avcodec_send_frame() returned %08X", ret);
        return NO;
    }
}

- (BOOL)receivePacketFromEncoderWithResult:(int *)result
{
    if (self.isEOF) {
        if (result) *result = AVERROR_EOF;
        return NO;
    }
    
    if (!encoded) {                                   // Prepare encoded packet
        encoded = av_packet_alloc();
        if (!encoded) {
            SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Failed to allocate a video packet.");
            if (result) *result = AVERROR(ENOMEM);
            return NO;
        }
    }
    
    int ret = avcodec_receive_packet(avctx, encoded);
    if (result) *result = ret;
    
    if (ret == 0) {
        return YES;
    } else if (ret == AVERROR(EAGAIN)) {                   // Encoder requests more input
        return YES; // Not an error, just needs more input
    } else if (ret == AVERROR_EOF) {                       // Fully flushed out
        self.isEOF = YES;
        return YES; // EOF is a valid state
    } else {
        SecureErrorLogf(@"[MEEncoderPipeline] ERROR: Failed to avcodec_receive_packet().");
        return NO;
    }
}

- (BOOL)flushEncoderWithResult:(int *)result
{
    return [self sendFrameToEncoder:NULL withResult:result];
}

- (void *)encodedPacket
{
    return encoded;
}

- (void)getPixelFormatSpec:(void *)spec
{
    if (spec) {
        memcpy(spec, &pxl_fmt_encode, sizeof(struct AVFPixelFormatSpec));
    }
}

@end
