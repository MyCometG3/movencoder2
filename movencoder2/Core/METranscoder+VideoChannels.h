//
//  METranscoder+VideoChannels.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef METranscoder_VideoChannels_h
#define METranscoder_VideoChannels_h

#import "MECommon.h"
#import "METranscoder.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder (VideoChannels)

/**
 * @brief Setup video encoding channels with AVFoundation
 *
 * Configures video channels for encoding using AVAssetReader/AVAssetWriter.
 * Applies compression settings, field mode, and color properties.
 * Falls back to copy mode if videoEncode is disabled.
 *
 * @param movie Source movie
 * @param ar Asset reader
 * @param aw Asset writer
 */
- (void) prepareVideoChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

/**
 * @brief Setup video processing channels with MEManager
 *
 * Configures video channels for processing using MEManager.
 * Provides advanced video processing capabilities and can operate
 * in either encoding or passthrough mode based on configuration.
 *
 * @param movie Source movie
 * @param ar Asset reader
 * @param aw Asset writer
 */
- (void) prepareVideoMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

@end

NS_ASSUME_NONNULL_END

#endif /* METranscoder_VideoChannels_h */
