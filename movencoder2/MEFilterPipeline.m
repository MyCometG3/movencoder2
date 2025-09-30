//
//  MEFilterPipeline.m
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

#import "MEFilterPipeline.h"
#import "MECommon.h"
#import "MEUtils.h"
#import "MESecureLogging.h"
#import "MEErrorFormatter.h"

// FFmpeg pixel format list (extern from MEManager)
extern enum AVPixelFormat pix_fmt_list[];

NS_ASSUME_NONNULL_BEGIN

@interface MEFilterPipeline ()
{
    struct AVFPixelFormatSpec pxl_fmt_filter;
    AVFilterContext *buffersink_ctx;
    AVFilterContext *buffersrc_ctx;
    AVFilterGraph *filter_graph;
    AVFrame *filtered;
    int64_t lastDequeuedPTS;
}

@property (atomic, readwrite) BOOL isReady;
@property (atomic, readwrite) BOOL isEOF;
@property (atomic, readwrite) BOOL hasValidFilteredFrame;

@end

NS_ASSUME_NONNULL_END

@implementation MEFilterPipeline

@synthesize filterReadySemaphore = _filterReadySemaphore;
@synthesize timestampGapSemaphore = _timestampGapSemaphore;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _filterReadySemaphore = dispatch_semaphore_create(0);
        _timestampGapSemaphore = dispatch_semaphore_create(0);
        
        pxl_fmt_filter = AVFPixelFormatSpecNone;
        buffersink_ctx = NULL;
        buffersrc_ctx = NULL;
        filter_graph = NULL;
        filtered = NULL;
        lastDequeuedPTS = 0;
        
        _isReady = NO;
        _isEOF = NO;
        _hasValidFilteredFrame = NO;
        _verbose = NO;
        _logLevel = AV_LOG_ERROR;
        _timeBase = 0;
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    av_frame_free(&filtered);
    avfilter_graph_free(&filter_graph);
    
    // Reset contexts (they're freed by avfilter_graph_free)
    buffersink_ctx = NULL;
    buffersrc_ctx = NULL;
    
    self.isReady = NO;
    self.isEOF = NO;
    self.hasValidFilteredFrame = NO;
}

- (BOOL)prepareVideoFilterWith:(CMSampleBufferRef)sampleBuffer
{
    char *filters_descr = NULL;
    AVFilterInOut *outputs = NULL;
    AVFilterInOut *inputs = NULL;
    char args[512] = {0};

    if (self.isReady) {
        return YES;
    }
    
    if (!(self.filterString && self.filterString.length)) {
        SecureErrorLogf(@"[MEFilterPipeline] ERROR: Invalid video filter parameters.");
        goto end;
    }
    
    if (sampleBuffer == NULL) {
        SecureErrorLogf(@"[MEFilterPipeline] ERROR: Invalid video filter parameters.");
        goto end;
    }
    
    // Validate source CMSampleBuffer
    {
        int width = 0, height = 0;
        if (CMSBGetWidthHeight(sampleBuffer, &width, &height) == FALSE) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot validate dimensions.");
            goto end;
        }
        
        AVRational sample_aspect_ratio = av_make_q(1, 1);
        if (CMSBGetAspectRatio(sampleBuffer, &sample_aspect_ratio) == FALSE) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot validate aspect ratio.");
            goto end;
        }
        
        pxl_fmt_filter = AVFPixelFormatSpecNone;
        if (!(CMSBGetPixelFormatSpec(sampleBuffer, &pxl_fmt_filter) && pxl_fmt_filter.avf_id != 0)) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot validate pixel_format.");
            goto end;
        }
        
        AVRational timebase_q = av_make_q(1, self.timeBase);
        if (self.timeBase == 0) { // fallback
            if (CMSBGetTimeBase(sampleBuffer, &timebase_q)) {
                self.timeBase = timebase_q.den;
            } else {
                SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot validate timebase.");
                goto end;
            }
        }
        
        snprintf(args, sizeof(args),
                 "video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d",
                 width, height, pxl_fmt_filter.ff_id,
                 timebase_q.num, timebase_q.den,
                 sample_aspect_ratio.num, sample_aspect_ratio.den);
        
        if (self.verbose) {
            SecureDebugLogf(@"[MEFilterPipeline] avfilter.buffer = %@", [NSString stringWithUTF8String:args]);
        }
    }
    
    // Update log_level
    av_log_set_level(self.logLevel);
    
    // Initialize AVFilter
    {
        int ret = AVERROR_UNKNOWN;
        filter_graph = avfilter_graph_alloc();
        
        /* buffer video source: the decoded frames from the decoder will be inserted here. */
        const AVFilter *buffersrc = avfilter_get_by_name("buffer");
        ret = avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in",
                                           args, NULL, filter_graph);
        if (ret < 0) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot create buffer source (%@)", [MEErrorFormatter stringFromFFmpegCode:ret]);
            goto end;
        }
        
        /* buffer video sink: to terminate the filter chain. */
        const AVFilter *buffersink = avfilter_get_by_name("buffersink");
        buffersink_ctx = avfilter_graph_alloc_filter(filter_graph, buffersink, "out");
        if (!buffersink_ctx) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot create buffer sink (%@)", [MEErrorFormatter stringFromFFmpegCode:AVERROR_UNKNOWN]);
            goto end;
        }
        
        // Set pixel formats for buffersink
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
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot set output pixel format (%@)", [MEErrorFormatter stringFromFFmpegCode:ret]);
            goto end;
        }
        
        ret = avfilter_init_str(buffersink_ctx, NULL);
        if (ret < 0) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot initialize buffer sink (%@)", [MEErrorFormatter stringFromFFmpegCode:ret]);
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
        outputs->name = av_strdup("in");
        outputs->filter_ctx = buffersrc_ctx;
        outputs->pad_idx = 0;
        outputs->next = NULL;
        
        /*
         * The buffer sink input must be connected to the output pad of
         * the last filter described by filters_descr; since the last
         * filter output label is not specified, it is set to "out" by
         * default.
         */
        inputs = avfilter_inout_alloc();
        inputs->name = av_strdup("out");
        inputs->filter_ctx = buffersink_ctx;
        inputs->pad_idx = 0;
        inputs->next = NULL;
        
        filters_descr = av_strdup([self.filterString UTF8String]);
        if ((ret = avfilter_graph_parse_ptr(filter_graph, filters_descr,
                                            &inputs, &outputs, NULL)) < 0) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot parse filter descriptions. %@", [MEErrorFormatter stringFromFFmpegCode:ret]);
            goto end;
        }
        
        if ((ret = avfilter_graph_config(filter_graph, NULL)) < 0) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Cannot configure filter graph. %@", [MEErrorFormatter stringFromFFmpegCode:ret]);
            goto end;
        }
    }
    
    self.isReady = YES;
    
    // Signal that filter is ready
    dispatch_semaphore_signal(self.filterReadySemaphore);
    
    if (self.verbose) {
        char* dump = avfilter_graph_dump(filter_graph, NULL);
        if (dump) {
            size_t dump_len = strlen(dump);
            NSString *dumpStr = [NSString stringWithUTF8String:dump];
            SecureDebugMultiline([NSString stringWithFormat:@"[MEFilterPipeline] filter graph dump (%lu bytes) BEGIN", (unsigned long)dump_len], @"[MEFilterPipeline] filter graph dump END", dumpStr);
        }
        av_free(dump);
    }
    
end:
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
    av_free(filters_descr);
    
    return self.isReady;
}

- (BOOL)pullFilteredFrameWithResult:(int *)result
{
    if (self.isEOF) {
        if (result) *result = AVERROR_EOF;
        return NO;
    }
    
    if (!filtered) {                                  // Prepare filtered frame
        self.hasValidFilteredFrame = NO;
        filtered = av_frame_alloc();                  // allocate frame
        if (!filtered) {
            SecureErrorLogf(@"[MEFilterPipeline] ERROR: Failed to allocate a video frame.");
            if (result) *result = AVERROR(ENOMEM);
            return NO;
        }
    }
    
    if (!self.isReady) {
        SecureErrorLogf(@"[MEFilterPipeline] ERROR: the filtergraph is not ready.");
        if (result) *result = AVERROR_UNKNOWN;
        return NO;
    }
    
    if (self.hasValidFilteredFrame) {
        if (result) *result = 0;
        return YES;
    }

    // Update filtered with filter graph output
    int ret = av_buffersink_get_frame(buffersink_ctx, filtered);
    if (result) *result = ret;
    
    if (ret == 0) {
        self.hasValidFilteredFrame = YES;                          // filtered is now ready
        
        AVFilterLink *input = (buffersink_ctx->inputs)[0];
        AVRational filtered_time_base = input->time_base;
        AVRational bq = filtered_time_base;
        AVRational cq = av_make_q(1, self.timeBase);
        int64_t newpts = av_rescale_q(filtered->pts, bq, cq);
        filtered->pts = newpts;
        lastDequeuedPTS = newpts;
        
        // Signal timestamp gap semaphore when PTS is updated
        dispatch_semaphore_signal(self.timestampGapSemaphore);
        return YES;
    } else if (ret == AVERROR(EAGAIN)) {                   // Needs more frame to graph
        return YES; // Not an error, just needs more input
    } else if (ret == AVERROR_EOF) {                       // Filter has completed its job
        self.isEOF = YES;
        return YES; // EOF is a valid state
    } else {
        SecureErrorLogf(@"[MEFilterPipeline] ERROR: Failed to av_buffersink_get_frame() (%d)", ret);
        return NO;
    }
}

- (int64_t)lastDequeuedPTS
{
    return lastDequeuedPTS;
}

- (void)setLastDequeuedPTS:(int64_t)pts
{
    lastDequeuedPTS = pts;
}

- (BOOL)pushFrameToFilter:(void *)frame withResult:(int *)result
{
    if (!self.isReady) {
        if (result) *result = AVERROR_UNKNOWN;
        return NO;
    }
    
    // Allow NULL frame for flushing the filter graph (FFmpeg API)
    // OWNERSHIP: Use AV_BUFFERSRC_FLAG_KEEP_REF so caller retains ownership
    // and must call av_frame_unref() after this method returns
    int ret = av_buffersrc_add_frame_flags(buffersrc_ctx, (AVFrame *)frame, AV_BUFFERSRC_FLAG_KEEP_REF);
    if (result) *result = ret;
    
    if (ret < 0) {
        SecureErrorLogf(@"[MEFilterPipeline] ERROR: Failed to av_buffersrc_add_frame_flags() (%d)", ret);
        return NO;
    }
    
    return YES;
}

- (void *)filteredFrame
{
    return filtered;
}

- (void)resetFilteredFrame
{
    if (filtered) {
        // Cleanup internal filtered frame - we own this frame
        av_frame_unref(filtered);
    }
    self.hasValidFilteredFrame = NO;
}

@end
