//
//  MEH26xNALUtils.h
//  movencoder2
//
//  Created for refactoring on 2026/02/09.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header MEH26xNALUtils.h
 * @abstract Internal API - H.26x NAL unit utilities from FFmpeg
 * @discussion
 * This header provides NAL unit parsing utilities adapted from the FFmpeg project.
 * These functions help find NAL unit boundaries and parse NAL units in H.264/H.265 streams.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef MEH26xNALUtils_h
#define MEH26xNALUtils_h

@import Foundation;

#include <stdint.h>

/* =================================================================================== */
// MARK: - NAL Unit Utilities (from FFmpeg)
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

/**
 * Find the start code pattern (0x000001) in a buffer.
 * Adapted from FFmpeg libavformat/avc.c
 *
 * @param p Pointer to the start of the buffer to search.
 * @param end Pointer to the end of the buffer.
 * @return Pointer to the start code, or end+3 if not found.
 */
const uint8_t *_Nonnull avc_find_startcode(const uint8_t *_Nonnull p, const uint8_t *_Nonnull end);

/**
 * Parse NAL units and convert from Annex B format (with start codes) to AVCC format (with length prefixes).
 * Adapted from FFmpeg libavformat/movenc.c
 *
 * @param buf Pointer to pointer to the buffer containing NAL units. Will be replaced with new buffer on output.
 * @param size Pointer to the size of the buffer. Will be updated with new size on output.
 */
void avc_parse_nal_units(uint8_t *_Nonnull* _Nonnull buf, int *size);

NS_ASSUME_NONNULL_END

#endif /* MEH26xNALUtils_h */
