//
//  METranscoder+CodecHelpers.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef METranscoder_CodecHelpers_h
#define METranscoder_CodecHelpers_h

#import "MECommon.h"
#import "METranscoder.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

/**
 * @brief Convert FourCC string to uint32_t format ID
 *
 * @param fourCC FourCC string (at least 4 characters)
 * @return uint32_t format ID, or 0 if invalid
 */
uint32_t formatIDFor(NSString* fourCC);

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

@interface METranscoder (CodecHelpers)

/**
 * @brief Get audio format ID from configuration
 *
 * @return Audio format ID as uint32_t
 */
- (uint32_t) audioFormatID;

/**
 * @brief Get video format ID from configuration
 *
 * @return Video format ID as uint32_t
 */
- (uint32_t) videoFormatID;

/**
 * @brief Setup copy channel for specified media type
 *
 * @param movie Source movie
 * @param ar Asset reader
 * @param aw Asset writer
 * @param type Media type to copy
 */
- (void) prepareCopyChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw of:(AVMediaType)type;

/**
 * @brief Setup channels for other media types (text, subtitle, timecode, etc.)
 *
 * @param movie Source movie
 * @param ar Asset reader
 * @param aw Asset writer
 */
- (void) prepareOtherMediaChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

@end

NS_ASSUME_NONNULL_END

#endif /* METranscoder_CodecHelpers_h */
