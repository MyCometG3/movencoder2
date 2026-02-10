//
//  MEAudioConverter+VolumeControl.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef MEAudioConverter_VolumeControl_h
#define MEAudioConverter_VolumeControl_h

#import "MECommon.h"
#import "MEAudioConverter.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEAudioConverter (VolumeControl)

/**
 * @brief Apply volume/gain adjustment to an AVAudioPCMBuffer
 *
 * Applies dB-based volume adjustment to audio samples in the buffer.
 * Converts dB to linear multiplier using formula: multiplier = 10^(dB/20).
 * Handles Float32, Int16, and Int32 sample formats with appropriate clamping
 * for integer formats to prevent overflow. Supports both interleaved and
 * non-interleaved channel layouts.
 *
 * No adjustment is applied if volumeDb is 0.0.
 *
 * @param buffer AVAudioPCMBuffer to modify in-place
 */
- (void)applyVolumeToBuffer:(AVAudioPCMBuffer*)buffer;

@end

NS_ASSUME_NONNULL_END

#endif /* MEAudioConverter_VolumeControl_h */
