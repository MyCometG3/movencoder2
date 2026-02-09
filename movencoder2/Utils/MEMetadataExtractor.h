//
//  MEMetadataExtractor.h
//  movencoder2
//
//  Created for refactoring on 2026/02/09.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEMetadataExtractor.h
 * @abstract Internal API - CMSampleBuffer metadata extraction
 * @discussion
 * This header provides utilities for extracting metadata from CMSampleBuffer,
 * including timing, dimensions, color information, field info, and more.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEMetadataExtractor_h
#define MEMetadataExtractor_h

@import Foundation;
@import AVFoundation;
@import CoreMedia;

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>

// Metadata cache structure for preserving color information
struct AVFrameColorMetadata {
    int color_range;
    int color_primaries;
    int color_trc;
    int colorspace;
    int chroma_location;
};

/* =================================================================================== */
// MARK: - CMSampleBuffer metadata extraction functions
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Get timebase from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param timebase Pointer to store the timebase
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetTimeBase(CMSampleBufferRef sb, AVRational *timebase);

/**
 * @brief Get width and height from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param width Pointer to store the width
 * @param height Pointer to store the height
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetWidthHeight(CMSampleBufferRef sb, int *width, int *height);

/**
 * @brief Get crop information from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param left Pointer to store the left crop
 * @param right Pointer to store the right crop
 * @param top Pointer to store the top crop
 * @param bottom Pointer to store the bottom crop
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetCrop(CMSampleBufferRef sb, int *left, int *right, int *top, int *bottom);

/**
 * @brief Get aspect ratio from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param ratio Pointer to store the aspect ratio
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetAspectRatio(CMSampleBufferRef sb, AVRational* ratio);

/**
 * @brief Get field info from format description extensions
 * @param sourceExtensions The format description extensions dictionary
 * @param fieldCount Pointer to store the field count
 * @param top_field_first Pointer to store the top field first flag
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetFieldInfo_FDE(CFDictionaryRef sourceExtensions, int *fieldCount, int *top_field_first);

/**
 * @brief Get field info from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param fieldCount Pointer to store the field count
 * @param top_field_first Pointer to store the top field first flag
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetFieldInfo(CMSampleBufferRef sb, int *fieldCount, int *top_field_first);

/**
 * @brief Get color primaries from format description extensions
 * @param sourceExtensions The format description extensions dictionary
 * @param pri Pointer to store the color primaries value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetColorPRI_FDE(CFDictionaryRef sourceExtensions, int *pri);

/**
 * @brief Get color primaries from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param pri Pointer to store the color primaries value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetColorPRI(CMSampleBufferRef sb, int *pri);

/**
 * @brief Get color transfer characteristics from format description extensions
 * @param sourceExtensions The format description extensions dictionary
 * @param trc Pointer to store the transfer characteristic value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetColorTRC_FDE(CFDictionaryRef sourceExtensions, int *trc);

/**
 * @brief Get color transfer characteristics from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param trc Pointer to store the transfer characteristic value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetColorTRC(CMSampleBufferRef sb, int *trc);

/**
 * @brief Get color space from format description extensions
 * @param sourceExtensions The format description extensions dictionary
 * @param spc Pointer to store the color space value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetColorSPC_FDE(CFDictionaryRef sourceExtensions, int *spc);

/**
 * @brief Get color space from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param spc Pointer to store the color space value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetColorSPC(CMSampleBufferRef sb, int* spc);

/**
 * @brief Get chroma location from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param loc Pointer to store the chroma location value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetChromaLoc(CMSampleBufferRef sb, int* loc);

/**
 * @brief Get color range from a CMSampleBuffer
 * @param sb The sample buffer to query
 * @param range Pointer to store the color range value
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBGetColorRange(CMSampleBufferRef sb, int*range);

/**
 * @brief Copy parameters from CMSampleBuffer to AVFrame
 * @param sb The sample buffer source
 * @param input The AVFrame destination
 * @param mediaTimeScale The media timescale
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBCopyParametersToAVFrame(CMSampleBufferRef sb, AVFrame *input, CMTimeScale mediaTimeScale);

/**
 * @brief Copy image buffer from CMSampleBuffer to AVFrame
 * @param sb The sample buffer source
 * @param input The AVFrame destination
 * @return TRUE if successful, FALSE otherwise
 */
BOOL CMSBCopyImageBufferToAVFrame(CMSampleBufferRef sb, AVFrame *input);

/**
 * @brief Reset AVFrame properties to defaults
 * @param input The AVFrame to reset
 */
void AVFrameReset(AVFrame *input);

/**
 * @brief Fill AVFrame metadata from cached metadata
 * @param filtered The AVFrame to fill
 * @param cachedMetadata The cached metadata to use
 */
void AVFrameFillMetadataFromCache(AVFrame *filtered, const struct AVFrameColorMetadata *cachedMetadata);

/**
 * @brief Create a CVPixelBuffer pool from an AVFrame
 * @param filtered The AVFrame to use as template
 * @return CVPixelBufferPoolRef or NULL on failure
 */
_Nullable CVPixelBufferPoolRef AVFrameCreateCVPixelBufferPool(AVFrame* filtered);

/**
 * @brief Create a CVPixelBuffer from an AVFrame using a pool
 * @param filtered The AVFrame source
 * @param cvpbpool The CVPixelBuffer pool to use
 * @return CVPixelBufferRef or NULL on failure
 */
_Nullable CVPixelBufferRef AVFrameCreateCVPixelBuffer(AVFrame* filtered, CVPixelBufferPoolRef cvpbpool);

/**
 * @brief Create CVBuffer attachments dictionary from an AVFrame
 * @param filtered The AVFrame source
 * @return CFDictionaryRef with attachments or NULL on failure
 */
_Nullable CFDictionaryRef AVFrameCreateCVBufferAttachments(AVFrame *filtered);

NS_ASSUME_NONNULL_END

#endif /* MEMetadataExtractor_h */
