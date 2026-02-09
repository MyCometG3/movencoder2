//
//  METranscoder+AudioChannels.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef METranscoder_AudioChannels_h
#define METranscoder_AudioChannels_h

#import "MECommon.h"
#import "METranscoder.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder (AudioChannels)

/**
 * @brief Setup audio encoding channels with AVFoundation
 *
 * Configures audio channels for encoding using AVAssetReader/AVAssetWriter.
 * Handles channel layout mapping, codec adjustments, and bitrate validation.
 * Falls back to copy mode if audioEncode is disabled.
 *
 * @param movie Source movie
 * @param ar Asset reader
 * @param aw Asset writer
 */
- (void) prepareAudioMediaChannelWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

/**
 * @brief Setup audio processing channels with MEAudioConverter
 *
 * Configures audio channels for processing using MEAudioConverter.
 * Provides advanced audio processing capabilities including format conversion
 * and channel layout remapping. Falls back to standard encoding if no
 * MEAudioConverter is registered for the track.
 *
 * @param movie Source movie
 * @param ar Asset reader
 * @param aw Asset writer
 */
- (void) prepareAudioMEChannelsWith:(AVMovie*)movie from:(AVAssetReader*)ar to:(AVAssetWriter*)aw;

@end

NS_ASSUME_NONNULL_END

#endif /* METranscoder_AudioChannels_h */
