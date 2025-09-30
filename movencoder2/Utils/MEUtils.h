//
//  MEUtils.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2019/01/19.
//  Copyright © 2019-2025 MyCometG3. All rights reserved.
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

#ifndef MEUtils_h
#define MEUtils_h

@import Foundation;
@import AVFoundation;
@import CoreMedia;

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
#include <libavutil/opt.h>
#include <libavutil/imgutils.h>
#include <libavutil/time.h>
#include <libavutil/version.h>
#include <libavcodec/videotoolbox.h>

/* =================================================================================== */
// MARK: - AVFPixelFormatSpec definition
/* =================================================================================== */

// From ffmpeg/libavdevice/avfoundation.m
struct AVFPixelFormatSpec {
    enum AVPixelFormat ff_id;
    OSType avf_id;
};

// Metadata cache structure for preserving color information
struct AVFrameColorMetadata {
    int color_range;
    int color_primaries;
    int color_trc;
    int colorspace;
    int chroma_location;
};

// From ffmpeg/libavdevice/avfoundation.m
static const struct AVFPixelFormatSpec avf_pixel_formats[] = {
    { AV_PIX_FMT_MONOBLACK,    kCVPixelFormatType_1Monochrome },
    { AV_PIX_FMT_RGB555BE,     kCVPixelFormatType_16BE555 },
    { AV_PIX_FMT_RGB555LE,     kCVPixelFormatType_16LE555 },
    { AV_PIX_FMT_RGB565BE,     kCVPixelFormatType_16BE565 },
    { AV_PIX_FMT_RGB565LE,     kCVPixelFormatType_16LE565 },
    { AV_PIX_FMT_RGB24,        kCVPixelFormatType_24RGB },
    { AV_PIX_FMT_BGR24,        kCVPixelFormatType_24BGR },
    { AV_PIX_FMT_0RGB,         kCVPixelFormatType_32ARGB },
    { AV_PIX_FMT_BGR0,         kCVPixelFormatType_32BGRA },
    { AV_PIX_FMT_0BGR,         kCVPixelFormatType_32ABGR },
    { AV_PIX_FMT_RGB0,         kCVPixelFormatType_32RGBA },
    { AV_PIX_FMT_BGR48BE,      kCVPixelFormatType_48RGB },
    
    { AV_PIX_FMT_UYVY422,      kCVPixelFormatType_422YpCbCr8 }, // *** '2vuy' Cb Y0 Cr Y1
    
    { AV_PIX_FMT_YUVA444P,     kCVPixelFormatType_4444YpCbCrA8R },
    { AV_PIX_FMT_YUVA444P16LE, kCVPixelFormatType_4444AYpCbCr16 },
    { AV_PIX_FMT_YUV444P,      kCVPixelFormatType_444YpCbCr8 },
    { AV_PIX_FMT_YUV422P16,    kCVPixelFormatType_422YpCbCr16 },
    { AV_PIX_FMT_YUV422P10,    kCVPixelFormatType_422YpCbCr10 },
    { AV_PIX_FMT_YUV444P10,    kCVPixelFormatType_444YpCbCr10 },
    { AV_PIX_FMT_YUV420P,      kCVPixelFormatType_420YpCbCr8Planar }, // *** 'y420'
    { AV_PIX_FMT_NV12,         kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange },
    
    { AV_PIX_FMT_YUYV422,      kCVPixelFormatType_422YpCbCr8_yuvs },
#if !TARGET_OS_IPHONE && __MAC_OS_X_VERSION_MIN_REQUIRED >= 1080
    { AV_PIX_FMT_GRAY8,        kCVPixelFormatType_OneComponent8 },
#endif
    { AV_PIX_FMT_NONE, 0 }
};

//
static const struct AVFPixelFormatSpec AVFPixelFormatSpecNone = { AV_PIX_FMT_NONE, 0 };
// 420 Planar
static const struct AVFPixelFormatSpec AVFPixelFormatSpec420P = { AV_PIX_FMT_YUV420P, kCVPixelFormatType_420YpCbCr8Planar };
// 422 Component
static const struct AVFPixelFormatSpec AVFPixelFormatSpecYUYV = { AV_PIX_FMT_YUYV422, kCVPixelFormatType_422YpCbCr8_yuvs };
static const struct AVFPixelFormatSpec AVFPixelFormatSpecUYVY = { AV_PIX_FMT_UYVY422, kCVPixelFormatType_422YpCbCr8 }; // 2vuy
// 444 Planar
static const struct AVFPixelFormatSpec AVFPixelFormatSpec444P = { AV_PIX_FMT_YUV444P, kCVPixelFormatType_444YpCbCr8 };

/* =================================================================================== */
// MARK: - Utility functions
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

BOOL CMSBGetPixelFormatType(CMSampleBufferRef sb, OSType *type);
BOOL CMSBGetPixelFormatSpec(CMSampleBufferRef sb, struct AVFPixelFormatSpec *spec);
BOOL AVFrameGetPixelFormatSpec(AVFrame *frame, struct AVFPixelFormatSpec *spec);
BOOL CMSBGetTimeBase(CMSampleBufferRef sb, AVRational *timebase);
BOOL CMSBGetWidthHeight(CMSampleBufferRef sb, int *width, int *height);
BOOL CMSBGetCrop(CMSampleBufferRef sb, int *left, int *right, int *top, int *bottom);
BOOL CMSBGetAspectRatio(CMSampleBufferRef sb, AVRational* ratio);
BOOL CMSBGetFieldInfo_FDE(CFDictionaryRef sourceExtensions, int *fieldCount, int *top_field_first);
BOOL CMSBGetFieldInfo(CMSampleBufferRef sb, int *fieldCount, int *top_field_first);
BOOL CMSBGetColorPRI_FDE(CFDictionaryRef sourceExtensions, int *pri);
BOOL CMSBGetColorPRI(CMSampleBufferRef sb, int *pri);
BOOL CMSBGetColorTRC_FDE(CFDictionaryRef sourceExtensions, int *trc);
BOOL CMSBGetColorTRC(CMSampleBufferRef sb, int *trc);
BOOL CMSBGetColorSPC_FDE(CFDictionaryRef sourceExtensions, int *spc);
BOOL CMSBGetColorSPC(CMSampleBufferRef sb, int* spc);
BOOL CMSBGetChromaLoc(CMSampleBufferRef sb, int* loc);
BOOL CMSBGetColorRange(CMSampleBufferRef sb, int*range);
BOOL CMSBCopyParametersToAVFrame(CMSampleBufferRef sb, AVFrame *input, CMTimeScale mediaTimeScale);
BOOL CMSBCopyImageBufferToAVFrame(CMSampleBufferRef sb, AVFrame *input);
void AVFrameReset(AVFrame *input);
void AVFrameFillMetadataFromCache(AVFrame *filtered, const struct AVFrameColorMetadata *cachedMetadata);

_Nullable CVPixelBufferPoolRef AVFrameCreateCVPixelBufferPool(AVFrame* filtered);
_Nullable CVPixelBufferRef AVFrameCreateCVPixelBuffer(AVFrame* filtered, CVPixelBufferPoolRef cvpbpool);
_Nullable CFDictionaryRef AVFrameCreateCVBufferAttachments(AVFrame *filtered);
_Nullable CMFormatDescriptionRef createDescriptionH264(AVCodecContext* avctx);
_Nullable CMFormatDescriptionRef createDescriptionH265(AVCodecContext* avctx);
_Nullable CMFormatDescriptionRef createDescriptionWithAperture(CMFormatDescriptionRef inDesc, NSValue* cleanApertureValue);

void avc_parse_nal_units(uint8_t *_Nonnull* _Nonnull buf, int *size);

NS_ASSUME_NONNULL_END

#endif /* MEUtils_h */
