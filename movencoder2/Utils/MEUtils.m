//
//  MEUtils.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2019/01/19.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEUtils.h"
#import "MECodecUtils.h"
#import "MEH26xNALUtils.h"

NS_ASSUME_NONNULL_BEGIN

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

static inline BOOL strEqual(CFStringRef a, CFStringRef b) {
    if (a && b) {
        CFComparisonResult result = CFStringCompare(a, b, 0);
        return (result == kCFCompareEqualTo);
    }
    return FALSE;
}

BOOL CMSBGetPixelFormatType(CMSampleBufferRef sb, OSType *type) {
    CVImageBufferRef ib = CMSampleBufferGetImageBuffer(sb);
    if (ib) {
        OSType pixelFormatType = CVPixelBufferGetPixelFormatType(ib);
        *type = pixelFormatType;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetPixelFormatSpec(CMSampleBufferRef sb, struct AVFPixelFormatSpec *spec) {
    struct AVFPixelFormatSpec pixelFormatSpec;
    OSType type = 0;
    if (CMSBGetPixelFormatType(sb, &type)) {
        for (int i = 0; avf_pixel_formats[i].ff_id != AV_PIX_FMT_NONE; i++) {
            if (type == avf_pixel_formats[i].avf_id) {
                pixelFormatSpec = avf_pixel_formats[i];
                *spec = pixelFormatSpec;
                return TRUE;
            }
        }
    }
    return FALSE;
}

BOOL AVFrameGetPixelFormatSpec(AVFrame *frame, struct AVFPixelFormatSpec *spec) {
    struct AVFPixelFormatSpec pixelFormatSpec;
    int format = frame->format; // AVPixelFormat
    if (format != AV_PIX_FMT_NONE) {
        for (int i = 0; avf_pixel_formats[i].ff_id != AV_PIX_FMT_NONE; i++) {
            if (format == avf_pixel_formats[i].ff_id) {
                pixelFormatSpec = avf_pixel_formats[i];
                *spec = pixelFormatSpec;
                return TRUE;
            }
        }
    }
    return FALSE;
}

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

BOOL CMSBGetTimeBase(CMSampleBufferRef sb, AVRational *timebase) {
    CMItemCount count = 0;
    CMSampleTimingInfo timing_info = kCMTimingInfoInvalid;
    OSStatus err = CMSampleBufferGetOutputSampleTimingInfoArray(sb, 1, &timing_info, &count);
    if (err == noErr && count == 1) {
        AVRational timebase_q = av_make_q(1, timing_info.presentationTimeStamp.timescale);
        *timebase = timebase_q;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetWidthHeight(CMSampleBufferRef sb, int *width, int *height) {
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(desc);
        *width = dims.width;
        *height = dims.height;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetCrop(CMSampleBufferRef sb, int *left, int *right, int *top, int *bottom) {
    int crop_left, crop_top, crop_right, crop_bottom;
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(desc);
        CGRect cleanRect = CMVideoFormatDescriptionGetCleanAperture(desc, TRUE);
        CGPoint cleanOrigin = cleanRect.origin;
        CGSize cleanSize = cleanRect.size;
        if (dims.width == cleanSize.width && dims.height == cleanSize.height) {
            crop_left = 0;
            crop_top = 0;
            crop_right = dims.width;
            crop_bottom = dims.height;
        } else {
            crop_left = cleanOrigin.x;
            crop_top = cleanOrigin.y;
            crop_right = dims.width - (cleanOrigin.x + cleanSize.width);
            crop_bottom = dims.height - (cleanOrigin.y + cleanSize.height);
        }
        *left = crop_left;
        *top = crop_top;
        *right = crop_right;
        *bottom = crop_bottom;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetAspectRatio(CMSampleBufferRef sb, AVRational* ratio) {
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        AVRational sample_aspect_ratio = av_make_q(1, 1);
        CFDictionaryRef dict = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_PixelAspectRatio);
        if (dict) {
            CFNumberRef hNum = CFDictionaryGetValue(dict, kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing);
            CFNumberRef vNum = CFDictionaryGetValue(dict, kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing);
            if (hNum && vNum) {
                int hSpacing = 1, vSpacing = 1;
                CFNumberGetValue(hNum, kCFNumberIntType, &hSpacing);
                CFNumberGetValue(vNum, kCFNumberIntType, &vSpacing);
                sample_aspect_ratio = av_make_q(hSpacing, vSpacing);
            }
        }
        *ratio = sample_aspect_ratio;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetFieldInfo_FDE(CFDictionaryRef sourceExtensions, int *fieldCount, int *top_field_first){
    if (sourceExtensions) {
        CFNumberRef numCount = CFDictionaryGetValue(sourceExtensions, kCMFormatDescriptionExtension_FieldCount);
        CFStringRef detail = CFDictionaryGetValue(sourceExtensions, kCMFormatDescriptionExtension_FieldDetail);
        *fieldCount = 1;
        *top_field_first = 0;
        int intCount = 1;
        if (numCount && CFNumberGetValue(numCount, kCFNumberIntType, &intCount) && intCount == 2) {
            if (detail) {
                // Only interleaved (woven) imageBuffer is supported (No segmented frame is supported)
                if (strEqual(detail, kCVImageBufferFieldDetailSpatialFirstLineEarly)) { // detail==9
                    *fieldCount = 2;
                    *top_field_first = 1;
                } else if (strEqual(detail, kCVImageBufferFieldDetailSpatialFirstLineLate)) { // detail==14
                    *fieldCount = 2;
                    *top_field_first = 0;
                }
            }
        }
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetFieldInfo(CMSampleBufferRef sb, int *fieldCount, int *top_field_first){
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        *fieldCount = 1;
        *top_field_first = 0;
        int intCount = 1;
        CFNumberRef numCount = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldCount);
        if (numCount && CFNumberGetValue(numCount, kCFNumberIntType, &intCount) && intCount == 2) {
            CFStringRef detail = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldDetail);
            if (detail) {
                // Only interleaved (woven) imageBuffer is supported (No segmented frame is supported)
                if (strEqual(detail, kCVImageBufferFieldDetailSpatialFirstLineEarly)) { // detail==9
                    *fieldCount = 2;
                    *top_field_first = 1;
                } else if (strEqual(detail, kCVImageBufferFieldDetailSpatialFirstLineLate)) { // detail==14
                    *fieldCount = 2;
                    *top_field_first = 0;
                }
            }
        }
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetColorPRI_FDE(CFDictionaryRef sourceExtensions, int *pri) {
    if (sourceExtensions) {
        CFStringRef primaries = CFDictionaryGetValue(sourceExtensions, kCMFormatDescriptionExtension_ColorPrimaries);
        int color_primaries = AVCOL_PRI_UNSPECIFIED;
        if (primaries) {
            color_primaries = CVColorPrimariesGetIntegerCodePointForString(primaries);
        }
        *pri = color_primaries;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetColorPRI(CMSampleBufferRef sb, int *pri) {
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        int color_primaries = AVCOL_PRI_UNSPECIFIED;
        CFStringRef primaries = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_ColorPrimaries);
        if (primaries) {
            color_primaries = CVColorPrimariesGetIntegerCodePointForString(primaries);
        }
        *pri = color_primaries;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetColorTRC_FDE(CFDictionaryRef sourceExtensions, int *trc) {
    if (sourceExtensions) {
        CFStringRef transfer = CFDictionaryGetValue(sourceExtensions,
                                                    kCMFormatDescriptionExtension_TransferFunction);
        CFNumberRef num = CFDictionaryGetValue(sourceExtensions,
                                               kCMFormatDescriptionExtension_GammaLevel);
        
        int color_trc = AVCOL_TRC_UNSPECIFIED;
        if (transfer) {
            color_trc = CVTransferFunctionGetIntegerCodePointForString(transfer);
            *trc = color_trc; // AVCOL_TRC_*
            return TRUE;
        }
        if (num != NULL) {
            double gamma = 0;
            if (CFNumberGetValue(num, kCFNumberDoubleType, &gamma)) {
                if (fabs(2.2 - gamma) < 0.1)
                    color_trc = AVCOL_TRC_GAMMA22; // 4
                else if (fabs(2.8 - gamma) < 0.1)
                    color_trc = AVCOL_TRC_GAMMA28; // 5
            }
            *trc = color_trc; // AVCOL_TRC_*
            return TRUE;
        }
    }
    return FALSE;
}

BOOL CMSBGetColorTRC(CMSampleBufferRef sb, int *trc) {
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        int color_trc = AVCOL_TRC_UNSPECIFIED;
        CFStringRef transfer = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_TransferFunction);
        if (transfer) {
            color_trc = CVTransferFunctionGetIntegerCodePointForString(transfer);
            if (strEqual(transfer, kCMFormatDescriptionTransferFunction_UseGamma)) {
                color_trc = AVCOL_TRC_UNSPECIFIED;
                double gamma = 0;
                CFNumberRef num = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_GammaLevel);
                if (num != NULL && CFNumberGetValue(num, kCFNumberDoubleType, &gamma)) {
                    if (fabs(2.2 - gamma) < 0.1)
                        color_trc = AVCOL_TRC_GAMMA22; // 4
                    else if (fabs(2.8 - gamma) < 0.1)
                        color_trc = AVCOL_TRC_GAMMA28; // 5
                }
            }
        }
        *trc = color_trc; // AVCOL_TRC_*
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetColorSPC_FDE(CFDictionaryRef sourceExtensions, int *spc) {
    if (sourceExtensions) {
        CFStringRef matrix = CFDictionaryGetValue(sourceExtensions, kCMFormatDescriptionExtension_YCbCrMatrix);
        int colorspace = AVCOL_SPC_UNSPECIFIED;
        if (matrix) {
            colorspace = CVYCbCrMatrixGetIntegerCodePointForString(matrix);
        }
        *spc = colorspace; // AVCOL_SPC_*
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetColorSPC(CMSampleBufferRef sb, int* spc) {
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        int colorspace = AVCOL_SPC_UNSPECIFIED;
        CFStringRef matrix = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_YCbCrMatrix);
        if (matrix) {
            colorspace = CVYCbCrMatrixGetIntegerCodePointForString(matrix);
        }
        *spc = colorspace; // AVCOL_SPC_*
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetChromaLoc(CMSampleBufferRef sb, int* loc) {
    CMFormatDescriptionRef desc = CMSampleBufferGetFormatDescription(sb);
    if (desc) {
        int chroma_location = AVCHROMA_LOC_UNSPECIFIED;
        CFStringRef chromaTop = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_ChromaLocationTopField);
        if (chromaTop) {
            if (strEqual(chromaTop, kCMFormatDescriptionChromaLocation_Left))
                chroma_location = AVCHROMA_LOC_LEFT;
            else if (strEqual(chromaTop, kCMFormatDescriptionChromaLocation_Center))
                chroma_location = AVCHROMA_LOC_CENTER;
            else if (strEqual(chromaTop, kCMFormatDescriptionChromaLocation_TopLeft))
                chroma_location = AVCHROMA_LOC_TOPLEFT;
            else if (strEqual(chromaTop, kCMFormatDescriptionChromaLocation_Top))
                chroma_location = AVCHROMA_LOC_TOP;
            else if (strEqual(chromaTop, kCMFormatDescriptionChromaLocation_BottomLeft))
                chroma_location = AVCHROMA_LOC_BOTTOMLEFT;
            else if (strEqual(chromaTop, kCMFormatDescriptionChromaLocation_Bottom))
                chroma_location = AVCHROMA_LOC_BOTTOM;
            else
                chroma_location = AVCHROMA_LOC_UNSPECIFIED;
        }
        CFStringRef chromaBot = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_ChromaLocationBottomField);
        if (chromaBot) {
            // AVFrame does not support AVChromaLocation for Bottom Field. Ignore this.
        }
        *loc = chroma_location;
        return TRUE;
    }
    return FALSE;
}

BOOL CMSBGetColorRange(CMSampleBufferRef sb, int*range) {
    OSType type = 0;
    if (CMSBGetPixelFormatType(sb, &type)) {
        int colorRange = AVCOL_RANGE_UNSPECIFIED;
        switch (type) {
            case kCVPixelFormatType_422YpCbCr8:
            case kCVPixelFormatType_4444YpCbCrA8:
            case kCVPixelFormatType_4444YpCbCrA8R:
            case kCVPixelFormatType_4444AYpCbCr8:
            case kCVPixelFormatType_4444AYpCbCr16:
            case kCVPixelFormatType_444YpCbCr8:
            case kCVPixelFormatType_422YpCbCr16:
            case kCVPixelFormatType_422YpCbCr10:
            case kCVPixelFormatType_444YpCbCr10:
            case kCVPixelFormatType_420YpCbCr8Planar:
            case kCVPixelFormatType_422YpCbCr_4A_8BiPlanar:
            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            case kCVPixelFormatType_422YpCbCr8_yuvs:
            case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            case kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange:
            case kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange:
                colorRange = AVCOL_RANGE_MPEG;
                break;
                //
            case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            case kCVPixelFormatType_422YpCbCr8FullRange:
            case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            case kCVPixelFormatType_422YpCbCr10BiPlanarFullRange:
            case kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
                colorRange = AVCOL_RANGE_JPEG;
                break;
                //
            default:
                colorRange = AVCOL_RANGE_UNSPECIFIED;
                break;
        }
        *range = colorRange;
        return TRUE;
    }
    return FALSE;
}

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

BOOL CMSBCopyParametersToAVFrame(CMSampleBufferRef sb, AVFrame *input, CMTimeScale mediaTimeScale) {
    if (sb && input) {
        // Check Timing information
        CMItemCount count = 0;
        CMSampleTimingInfo timing_info = kCMTimingInfoInvalid;
        OSStatus err = CMSampleBufferGetOutputSampleTimingInfoArray(sb, 1, &timing_info, &count);
        if (err != noErr || count != 1) {
            goto end;
        }
        
        // Timing information
        CMTime convertedDUR = CMTimeConvertScale(timing_info.duration, mediaTimeScale, kCMTimeRoundingMethod_Default);
        CMTime convertedPTS = CMTimeConvertScale(timing_info.presentationTimeStamp, mediaTimeScale, kCMTimeRoundingMethod_Default);
        CMTime convertedDTS = CMTimeConvertScale(timing_info.decodeTimeStamp, mediaTimeScale, kCMTimeRoundingMethod_Default);
        input->duration = convertedDUR.value;
        input->pts = convertedPTS.value;
        input->pkt_dts = convertedDTS.value;
        
        // pixel aspect ratio
        AVRational ratio;
        if (CMSBGetAspectRatio(sb, &ratio)) {
            input->sample_aspect_ratio = ratio;
        } else {
            goto end;
        }
        
        // Clean aperture
        int left, right, top, bottom;
        if (CMSBGetCrop(sb, &left, &right, &top, &bottom)) {
            input->crop_left = left;
            input->crop_top = top;
            input->crop_right = right;
            input->crop_bottom = bottom;
        } else {
            goto end;
        }
        
        // Color primaries (decoded SB does not have )
        int pri;
        if (CMSBGetColorPRI(sb, &pri)) {
            input->color_primaries = pri;
        } else {
            goto end;
        }
        
        // Transfer characteristic
        int trc;
        if (CMSBGetColorTRC(sb, &trc)) {
            input->color_trc = trc;
        } else {
            goto end;
        }
        
        // Color space
        int spc;
        if (CMSBGetColorSPC(sb, &spc)) {
            input->colorspace = spc;
        } else {
            goto end;
        }
        
        // Color range
        int range;
        if (CMSBGetColorRange(sb, &range)) {
            input->color_range = range;
        } else {
            goto end;
        }
        
        // Chroma location
        int loc;
        if (CMSBGetChromaLoc(sb, &loc)) {
            input->chroma_location = loc;
        } else {
            goto end;
        }
        
        // FieldCount/FieldDetail
        int fieldCount = 1, top_field_first = 0;
        if (CMSBGetFieldInfo(sb, &fieldCount, &top_field_first)) {
            input->flags &= ~AV_FRAME_FLAG_INTERLACED;
            input->flags &= ~AV_FRAME_FLAG_TOP_FIELD_FIRST;
            if (fieldCount == 2) {
                input->flags |= AV_FRAME_FLAG_INTERLACED;
                if (top_field_first) {
                    input->flags |= AV_FRAME_FLAG_TOP_FIELD_FIRST;
                }
            }
        } else {
            goto end;
        }

        return TRUE;
    }
    
end:
    return FALSE;
}

BOOL CMSBCopyImageBufferToAVFrame(CMSampleBufferRef sb, AVFrame *input) {
    if (sb && input) {
        CVImageBufferRef image_buffer = CMSampleBufferGetImageBuffer(sb);
        if (!image_buffer) {
            goto end;
        }
        
        CVReturn err = kCVReturnSuccess;
        err = CVPixelBufferLockBaseAddress(image_buffer, kCVPixelBufferLock_ReadOnly);
        if (err != kCVReturnSuccess) {
            goto end;
        }
        
        uint8_t* src_data[4] = {};
        int src_linesize[4] = {};
        if (CVPixelBufferIsPlanar(image_buffer)) {
            size_t plane_count = CVPixelBufferGetPlaneCount(image_buffer);
            for (int i = 0; i < plane_count; i++) {
                src_linesize[i] = (int)CVPixelBufferGetBytesPerRowOfPlane(image_buffer, i);
                src_data[i] = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(image_buffer, i);
            }
        } else {
            src_linesize[0] = (int)CVPixelBufferGetBytesPerRow(image_buffer);
            src_data[0] = (uint8_t*)CVPixelBufferGetBaseAddress(image_buffer);
        }
        
        av_image_copy((input->data), input->linesize,
                      (const uint8_t **)src_data, (const int *)src_linesize,
                      input->format, input->width, input->height);
        
        err = CVPixelBufferUnlockBaseAddress(image_buffer, kCVPixelBufferLock_ReadOnly);
        if (err != kCVReturnSuccess) {
            goto end;
        }
        
        return TRUE;
    } else {
        goto end;
    }
    
end:
    return FALSE;

}
/* =================================================================================== */
// MARK: -
/* =================================================================================== */

void AVFrameReset(AVFrame *input) {
    // Reset properties to default: see libavutil/frame.h - frame_copy_props()
    input->pict_type = AV_PICTURE_TYPE_NONE;
    input->sample_aspect_ratio = av_make_q(0, 1);       // copy from sb
    input->crop_top = 0;                                // copy from sb
    input->crop_bottom = 0;                             // copy from sb
    input->crop_left = 0;                               // copy from sb
    input->crop_right = 0;                              // copy from sb
    input->pts = AV_NOPTS_VALUE;                        // copy from sb
    input->duration = 0;                                // copy from sb
    input->repeat_pict = 0;
    input->sample_rate = 0;
    input->opaque = NULL;
    input->pkt_dts = AV_NOPTS_VALUE;                    // copy from sb
    input->time_base = av_make_q(1, 1);                 // copy from sb
    input->quality = 0;
    input->best_effort_timestamp = AV_NOPTS_VALUE;
    input->flags = 0;
    input->decode_error_flags = 0;
    input->color_primaries = AVCOL_PRI_UNSPECIFIED;     // copy from sb
    input->color_trc = AVCOL_TRC_UNSPECIFIED;           // copy from sb
    input->colorspace = AVCOL_SPC_UNSPECIFIED;          // copy from sb
    input->chroma_location = AVCHROMA_LOC_UNSPECIFIED;  // copy from sb
    input->metadata = NULL;
}

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

CVPixelBufferPoolRef AVFrameCreateCVPixelBufferPool(AVFrame* filtered) {
    OSType type = 0;
    int width = filtered->width, height = filtered->height;
    
    struct AVFPixelFormatSpec spec = AVFPixelFormatSpecNone;
    if(!AVFrameGetPixelFormatSpec(filtered, &spec)) {
        return NULL;
    }
    type = spec.avf_id;
    
    CVReturn result = 0;
    CVPixelBufferPoolRef pool = NULL;
    NSDictionary *poolAttr = @{(NSString*)kCVPixelBufferPoolMinimumBufferCountKey:@4};
    NSDictionary *pbAttr = @{(NSString*)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithUnsignedInt:type],
                             (NSString*)kCVPixelBufferWidthKey: @(width),
                             (NSString*)kCVPixelBufferHeightKey: @(height)};
    result = CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                     (__bridge CFDictionaryRef _Nullable) poolAttr,
                                     (__bridge CFDictionaryRef _Nullable) pbAttr,
                                     &pool);
    if (result != kCVReturnSuccess || !pool) {
        return NULL;
    }
    
    return pool;
}

CVPixelBufferRef AVFrameCreateCVPixelBuffer(AVFrame* filtered, CVPixelBufferPoolRef cvpbpool) {
    // Create new PixelBuffer from PixelBufferPool
    CVPixelBufferRef pb = NULL;
    CVReturn result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,
                                                         cvpbpool,
                                                         &pb);
    if (result != kCVReturnSuccess || !pb) goto end;
    
    // Fill PixelBuffer image copied from filtered AVFrame
    if (CVPixelBufferLockBaseAddress(pb, 0) != kCVReturnSuccess) goto end;
    if (CVPixelBufferIsPlanar(pb)) {
        for (size_t index = 0; index < CVPixelBufferGetPlaneCount(pb); index++) {
            void* dst = CVPixelBufferGetBaseAddressOfPlane(pb, index);
            void* src = filtered->data[index];
            size_t dstStride = CVPixelBufferGetBytesPerRowOfPlane(pb, index);
            size_t srcStride = filtered->linesize[index];
            size_t rows = CVPixelBufferGetHeightOfPlane(pb, index);
            if (dstStride == srcStride) {
                memcpy(dst, src, srcStride * rows);
            } else {
                size_t numBytes = (srcStride < dstStride) ? srcStride : dstStride;
                for (size_t y = 0; y < rows; y++) {
                    memcpy(dst+y*dstStride, src+y*srcStride, numBytes);
                }
            }
        }
    } else {
        void* dst = CVPixelBufferGetBaseAddress(pb);
        void* src = filtered->data[0];
        size_t dstStride = CVPixelBufferGetBytesPerRow(pb);
        size_t srcStride = filtered->linesize[0];
        size_t rows = CVPixelBufferGetHeight(pb);
        if (dstStride == srcStride) {
            memcpy(dst, src, srcStride * rows);
        } else {
            size_t numBytes = (srcStride < dstStride) ? srcStride : dstStride;
            for (size_t y = 0; y < rows; y++) {
                memcpy(dst+y*dstStride, src+y*srcStride, numBytes);
            }
        }
    }
    if (CVPixelBufferUnlockBaseAddress(pb, 0) != kCVReturnSuccess) goto end;
    
    return pb;
    
end:
    CVPixelBufferRelease(pb);
    return NULL;
}

CFDictionaryRef AVFrameCreateCVBufferAttachments(AVFrame *filtered) {
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorDefault, 16,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);
    {   //clean apreture
        int left = (int)filtered->crop_left;
        int right = (int)filtered->crop_right;
        int top = (int)filtered->crop_top;
        int bottom = (int)filtered->crop_bottom;
        if (left || right || top || bottom) {
            NSString* keyClapWidth = (__bridge NSString*)kCVImageBufferCleanApertureWidthKey;
            NSString* keyClapHeight = (__bridge NSString*)kCVImageBufferCleanApertureHeightKey;
            NSString* keyClapHOffset = (__bridge NSString*)kCVImageBufferCleanApertureHorizontalOffsetKey;
            NSString* keyClapVOffset = (__bridge NSString*)kCVImageBufferCleanApertureVerticalOffsetKey;
            int width = (int)filtered->width;
            int height = (int)filtered->height;
            
            NSMutableDictionary *clap = [NSMutableDictionary dictionary];
            clap[keyClapWidth] = @(width - left - right);
            clap[keyClapHeight] = @(height - top - bottom);
            clap[keyClapHOffset] = @( (left-right)/2 );
            clap[keyClapVOffset] = @( (top-bottom)/2 );
            CFDictionaryAddValue(dict, kCVImageBufferCleanApertureKey, (__bridge CFDictionaryRef)clap);
        }
    }
    {   //pixel aspect ratio
        AVRational ratio = filtered->sample_aspect_ratio;
        if (ratio.den > 0 && ratio.num > 0) {
            NSString* keyPaspHS = (__bridge NSString*)kCVImageBufferPixelAspectRatioHorizontalSpacingKey;
            NSString* keyPaspVS = (__bridge NSString*)kCVImageBufferPixelAspectRatioVerticalSpacingKey;
            
            NSMutableDictionary *pasp = [NSMutableDictionary dictionary];
            pasp[keyPaspHS] = @(ratio.num);
            pasp[keyPaspVS] = @(ratio.den);
            CFDictionaryAddValue(dict, kCVImageBufferPixelAspectRatioKey, (__bridge CFDictionaryRef)pasp);
        }
    }
    {   //field count/field detail
        int interlaced_frame = (filtered->flags & AV_FRAME_FLAG_INTERLACED);
        int top_field_first = (filtered->flags & AV_FRAME_FLAG_TOP_FIELD_FIRST);
        if (interlaced_frame) {
            NSString *keyFielDetail9_SFLE = (__bridge NSString*)kCVImageBufferFieldDetailSpatialFirstLineEarly;
            NSString *keyFielDetail14_SFLL = (__bridge NSString*)kCVImageBufferFieldDetailSpatialFirstLineLate;
            
            NSNumber *count = @(2);
            NSString *detail = (top_field_first ? keyFielDetail9_SFLE : keyFielDetail14_SFLL);
            CFDictionaryAddValue(dict, kCVImageBufferFieldCountKey, (__bridge CFNumberRef)count);
            CFDictionaryAddValue(dict, kCVImageBufferFieldDetailKey, (__bridge CFStringRef)detail);
        } else {
            NSNumber *count = @(1);
            CFDictionaryAddValue(dict, kCVImageBufferFieldCountKey, (__bridge CFNumberRef)count);
        }
    }
    {   // ColorPrimaries
        int color_primaries = filtered->color_primaries;
        if (color_primaries != AVCOL_PRI_UNSPECIFIED) {
            CFStringRef value = NULL;
            value = CVColorPrimariesGetStringForIntegerCodePoint(color_primaries);
            if (value) {
                CFDictionaryAddValue(dict, kCVImageBufferColorPrimariesKey, value);
            }
        }
    }
    {   // ColorTransferFunction/Gamma
        int trc = filtered->color_trc;
        if (trc != AVCOL_TRC_UNSPECIFIED) {
            CFStringRef value = NULL;
            value = CVTransferFunctionGetStringForIntegerCodePoint(trc);
            if (value) {
                CFDictionaryAddValue(dict, kCVImageBufferTransferFunctionKey, value);
                
                if (value == kCVImageBufferTransferFunction_UseGamma) {
                    CFNumberRef gamma = NULL;
                    if (trc == AVCOL_TRC_GAMMA22) {
                        gamma = (__bridge CFNumberRef)@(2.2F);
                    } else if (trc == AVCOL_TRC_GAMMA28) {
                        gamma = (__bridge CFNumberRef)@(2.8F);
                    }
                    if (gamma != NULL) {
                        CFDictionaryAddValue(dict, kCVImageBufferGammaLevelKey, gamma);
                    }
                }
            }
        }
        else {
            CFNumberRef gamma = NULL;
            gamma = (__bridge CFNumberRef)@(2.2F);
            CFDictionaryAddValue(dict, kCVImageBufferGammaLevelKey, gamma);
        }
    }
    {   // Color Space
        int spc = filtered->colorspace;
        if (spc != AVCOL_SPC_UNSPECIFIED) {
            CFStringRef value = NULL;
            value = CVYCbCrMatrixGetStringForIntegerCodePoint(spc);
            if (value) {
                CFDictionaryAddValue(dict, kCVImageBufferYCbCrMatrixKey, value);
            }
        }
    }
    {   // chroma location top/bottom
        int loc = filtered->chroma_location;
        if (loc != AVCHROMA_LOC_UNSPECIFIED) {
            CFStringRef value = NULL;
            switch (loc) {
                case AVCHROMA_LOC_LEFT:
                    value = kCVImageBufferChromaLocation_Left;
                    break;
                case AVCHROMA_LOC_CENTER:
                    value = kCVImageBufferChromaLocation_Center;
                    break;
                case AVCHROMA_LOC_TOPLEFT:
                    value = kCVImageBufferChromaLocation_TopLeft;
                    break;
                case AVCHROMA_LOC_TOP:
                    value = kCVImageBufferChromaLocation_Top;
                    break;
                case AVCHROMA_LOC_BOTTOMLEFT:
                    value = kCVImageBufferChromaLocation_BottomLeft;
                    break;
                case AVCHROMA_LOC_BOTTOM:
                    value = kCVImageBufferChromaLocation_Bottom;
                    break;
                default:
                    break;
            }
            if (value) { // apply same value to both top/bottom field
                CFDictionaryAddValue(dict, kCVImageBufferChromaLocationTopFieldKey, value);
                CFDictionaryAddValue(dict, kCVImageBufferChromaLocationBottomFieldKey, value);
            }
        }
    }
    {
        // TODO: Ignore color_range for uncompressed buffer
    }
    
    CFDictionaryRef dictOut = CFDictionaryCreateCopy(kCFAllocatorDefault, dict);
    if (dictOut) {
        CFRelease(dict);
        return dictOut;
    } else {
        return NULL;
    }
}

void AVFrameFillMetadataFromCache(AVFrame *filtered, const struct AVFrameColorMetadata *cachedMetadata) {
    if (!filtered || !cachedMetadata) {
        return;
    }
    
    // Copy missing color_range metadata from cache
    if (filtered->color_range == AVCOL_RANGE_UNSPECIFIED && cachedMetadata->color_range != AVCOL_RANGE_UNSPECIFIED) {
        filtered->color_range = cachedMetadata->color_range;
    }
    
    // Copy missing color_primaries metadata from cache
    if (filtered->color_primaries == AVCOL_PRI_UNSPECIFIED && cachedMetadata->color_primaries != AVCOL_PRI_UNSPECIFIED) {
        filtered->color_primaries = cachedMetadata->color_primaries;
    }
    
    // Copy missing color_trc metadata from cache
    if (filtered->color_trc == AVCOL_TRC_UNSPECIFIED && cachedMetadata->color_trc != AVCOL_TRC_UNSPECIFIED) {
        filtered->color_trc = cachedMetadata->color_trc;
    }
    
    // Copy missing colorspace metadata from cache
    if (filtered->colorspace == AVCOL_SPC_UNSPECIFIED && cachedMetadata->colorspace != AVCOL_SPC_UNSPECIFIED) {
        filtered->colorspace = cachedMetadata->colorspace;
    }
    
    // Copy missing chroma_location metadata from cache
    if (filtered->chroma_location == AVCHROMA_LOC_UNSPECIFIED && cachedMetadata->chroma_location != AVCHROMA_LOC_UNSPECIFIED) {
        filtered->chroma_location = cachedMetadata->chroma_location;
    }
}

NS_ASSUME_NONNULL_END
