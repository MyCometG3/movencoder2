//
//  MEPixelFormatUtils.h
//  movencoder2
//
//  Created for refactoring on 2026/02/09.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEPixelFormatUtils.h
 * @abstract Internal API - Pixel format utilities
 * @discussion
 * This header provides utilities for converting between AVFoundation/CoreVideo
 * pixel formats and FFmpeg pixel formats.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEPixelFormatUtils_h
#define MEPixelFormatUtils_h

@import Foundation;
@import AVFoundation;
@import CoreMedia;

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>

/* =================================================================================== */
// MARK: - AVFPixelFormatSpec definition
/* =================================================================================== */

// From ffmpeg/libavdevice/avfoundation.m
struct AVFPixelFormatSpec {
    enum AVPixelFormat ff_id;
    OSType avf_id;
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
// MARK: - Pixel format utility functions
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Get pixel format type from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param type Pointer to store the pixel format type
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetPixelFormatType(CMSampleBufferRef sb, OSType *type);

/**
 * @brief Get pixel format specification from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param spec Pointer to store the pixel format specification
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetPixelFormatSpec(CMSampleBufferRef sb, struct AVFPixelFormatSpec *spec);

/**
 * @brief Get pixel format specification from an AVFrame
 * @param frame The AVFrame to query
 * @param spec Pointer to store the pixel format specification
 * @return TRUE if successful, FALSE otherwise
 */
BOOL AVFrameGetPixelFormatSpec(AVFrame *frame, struct AVFPixelFormatSpec *spec);

NS_ASSUME_NONNULL_END

#endif /* MEPixelFormatUtils_h */
