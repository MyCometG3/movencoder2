//
//  MEAudioConverter+BufferConversion.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef MEAudioConverter_BufferConversion_h
#define MEAudioConverter_BufferConversion_h

#import "MECommon.h"
#import "MEAudioConverter.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@interface MEAudioConverter (BufferConversion)

/**
 * @brief Convert CMSampleBuffer to AVAudioPCMBuffer
 *
 * Extracts audio data from a CMSampleBuffer and creates an AVAudioPCMBuffer
 * in the specified format. Handles both interleaved and non-interleaved layouts.
 * Performs basic consistency checks on channel count and interleaving.
 *
 * @param sampleBuffer Source CMSampleBuffer containing audio data
 * @param format Target AVAudioFormat for the resulting PCM buffer
 * @return AVAudioPCMBuffer or nil if conversion fails
 */
- (nullable AVAudioPCMBuffer*) createPCMBufferFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
                                                    withFormat:(AVAudioFormat*)format;

/**
 * @brief Convert AVAudioPCMBuffer to CMSampleBuffer
 *
 * Creates a CMSampleBuffer from an AVAudioPCMBuffer with the specified format
 * and presentation timestamp. Handles both interleaved and non-interleaved layouts.
 * Validates format compatibility and channel layout consistency.
 *
 * @param pcmBuffer Source AVAudioPCMBuffer containing audio data
 * @param pts Presentation timestamp for the resulting sample buffer
 * @param format Target AVAudioFormat for the CMSampleBuffer
 * @return CMSampleBufferRef or NULL if conversion fails (caller must release)
 */
- (nullable CMSampleBufferRef) createSampleBufferFromPCMBuffer:(AVAudioPCMBuffer*)pcmBuffer
                                   withPresentationTimeStamp:(CMTime)pts
                                                      format:(AVAudioFormat*)format
                                             CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END

#endif /* MEAudioConverter_BufferConversion_h */
