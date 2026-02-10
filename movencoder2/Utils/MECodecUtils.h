//
//  MECodecUtils.h
//  movencoder2
//
//  Created for refactoring on 2026/02/09.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MECodecUtils.h
 * @abstract Internal API - H.264/H.265 codec support utilities
 * @discussion
 * This header provides utilities for creating CMFormatDescription from
 * H.264 and H.265 codec contexts, and for manipulating format descriptions
 * with clean aperture information.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MECodecUtils_h
#define MECodecUtils_h

@import Foundation;
@import CoreMedia;

#include <libavcodec/avcodec.h>

/* =================================================================================== */
// MARK: - H.264/H.265 Codec Support Functions
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

/**
 * Create a CMFormatDescription from an H.264 AVCodecContext.
 *
 * @param avctx The AVCodecContext containing H.264 extradata (SPS/PPS).
 * @return A new CMFormatDescriptionRef, or NULL on failure. Caller is responsible for releasing.
 */
CF_RETURNS_RETAINED _Nullable CMFormatDescriptionRef createDescriptionH264(AVCodecContext* avctx);

/**
 * Create a CMFormatDescription from an H.265 AVCodecContext.
 *
 * @param avctx The AVCodecContext containing H.265 extradata (VPS/SPS/PPS).
 * @return A new CMFormatDescriptionRef, or NULL on failure. Caller is responsible for releasing.
 */
CF_RETURNS_RETAINED _Nullable CMFormatDescriptionRef createDescriptionH265(AVCodecContext* avctx);

/**
 * Create a new CMFormatDescription with clean aperture information.
 *
 * @param inDesc The input CMFormatDescription to base the new description on.
 * @param cleanApertureValue An NSValue containing an NSRect with clean aperture information.
 *        rect.origin.x = cWidth, rect.origin.y = cHeight,
 *        rect.size.width = hOffset, rect.size.height = vOffset
 * @return A new CMFormatDescriptionRef with clean aperture, or NULL on failure. Caller is responsible for releasing.
 */
CF_RETURNS_RETAINED _Nullable CMFormatDescriptionRef createDescriptionWithAperture(CMFormatDescriptionRef inDesc, NSValue* cleanApertureValue);

NS_ASSUME_NONNULL_END

#endif /* MECodecUtils_h */
