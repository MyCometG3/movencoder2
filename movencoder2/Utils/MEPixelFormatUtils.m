//
//  MEPixelFormatUtils.m
//  movencoder2
//
//  Created for refactoring on 2026/02/09.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEPixelFormatUtils.h"

NS_ASSUME_NONNULL_BEGIN

/* =================================================================================== */
// MARK: - Pixel format utilities
/* =================================================================================== */

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

NS_ASSUME_NONNULL_END
