//
//  METranscoder+CompressionSettings.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef METranscoder_CompressionSettings_h
#define METranscoder_CompressionSettings_h

#import "MECommon.h"
#import "METranscoder.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface METranscoder (CompressionSettings)

/**
 * @brief Check if track supports field mode decompression
 *
 * @param track Video track to check
 * @return YES if field mode is supported, NO otherwise
 */
- (BOOL) hasFieldModeSupportOf:(AVMovieTrack*)track;

/**
 * @brief Add decompression properties to reader output settings
 *
 * Adds field mode settings if supported by the track.
 *
 * @param track Video track
 * @param arOutputSetting Output settings to modify
 */
- (void) addDecommpressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting;

/**
 * @brief Build video compression settings for track
 *
 * Creates comprehensive video compression settings including:
 * - Codec and bitrate
 * - Clean aperture
 * - Pixel aspect ratio
 * - Color properties (NCLC)
 * - Field mode
 *
 * @param track Video track
 * @return Compression settings dictionary
 */
- (NSMutableDictionary<NSString*,id>*)videoCompressionSettingFor:(AVMovieTrack *)track;

@end

NS_ASSUME_NONNULL_END

#endif /* METranscoder_CompressionSettings_h */
