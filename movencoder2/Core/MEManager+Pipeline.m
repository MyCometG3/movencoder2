//
//  MEManager+Pipeline.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/12/02.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MEManager+Pipeline.h"
#import "MEManager+Internal.h"
#import "MECommon.h"
#import "MEUtils.h"
#import "MESecureLogging.h"
#import "MEFilterPipeline.h"
#import "MEEncoderPipeline.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEManager (Pipeline)

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

- (BOOL)prepareInputFrameWith:(CMSampleBufferRef)sb
{
    AVFrame *input = (AVFrame *)[self input];
    struct AVFPixelFormatSpec *pxl_fmt_filter = [self pxl_fmt_filter];
    struct AVFrameColorMetadata *cachedColorMetadata = [self cachedColorMetadata];
    CFDictionaryRef sourceExtensions = self.sourceExtensions;
    
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
        [self setValue:[NSValue valueWithPointer:input] forKey:@"input"];
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
        if (!(CMSBGetPixelFormatSpec(sb, pxl_fmt_filter) && pxl_fmt_filter->avf_id != 0)) {
            SecureErrorLogf(@"[MEManager] ERROR: Cannot validate pixel_format.");
            goto end;
        }
        input->format = pxl_fmt_filter->ff_id;
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
            cachedColorMetadata->color_range = input->color_range;
            cachedColorMetadata->color_primaries = input->color_primaries;
            cachedColorMetadata->color_trc = input->color_trc;
            cachedColorMetadata->colorspace = input->colorspace;
            cachedColorMetadata->chroma_location = input->chroma_location;
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

@end

NS_ASSUME_NONNULL_END
