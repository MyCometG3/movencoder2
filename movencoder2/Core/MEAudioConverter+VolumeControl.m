//
//  MEAudioConverter+VolumeControl.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECommon.h"
#import "MEAudioConverter+VolumeControl.h"
#import "MESecureLogging.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation MEAudioConverter (VolumeControl)

- (void)applyVolumeToBuffer:(AVAudioPCMBuffer*)buffer
{
    if (!buffer || self.volumeDb == 0.0) {
        return; // No volume adjustment needed
    }
    
    // Convert dB to linear multiplier: multiplier = 10^(dB/20)
    double volumeMultiplier = pow(10.0, self.volumeDb / 20.0);
    
    AVAudioFrameCount frameCount = buffer.frameLength;
    UInt32 channelCount = buffer.format.channelCount;
    
    switch (buffer.format.commonFormat) {
        case AVAudioPCMFormatFloat32: {
            if (buffer.format.isInterleaved) {
                // Interleaved format
                float* data = buffer.floatChannelData[0];
                for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                    for (UInt32 ch = 0; ch < channelCount; ch++) {
                        data[frame * channelCount + ch] *= volumeMultiplier;
                    }
                }
            } else {
                // Non-interleaved format
                for (UInt32 ch = 0; ch < channelCount; ch++) {
                    float* channelData = buffer.floatChannelData[ch];
                    if (channelData) {
                        for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                            channelData[frame] *= volumeMultiplier;
                        }
                    }
                }
            }
            break;
        }
        case AVAudioPCMFormatInt16: {
            if (buffer.format.isInterleaved) {
                // Interleaved format
                SInt16* data = buffer.int16ChannelData[0];
                for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                    for (UInt32 ch = 0; ch < channelCount; ch++) {
                        double sample = data[frame * channelCount + ch];
                        sample *= volumeMultiplier;
                        // Clamp to prevent overflow
                        if (sample > 32767.0) sample = 32767.0;
                        if (sample < -32768.0) sample = -32768.0;
                        data[frame * channelCount + ch] = (SInt16)sample;
                    }
                }
            } else {
                // Non-interleaved format
                for (UInt32 ch = 0; ch < channelCount; ch++) {
                    SInt16* channelData = buffer.int16ChannelData[ch];
                    if (channelData) {
                        for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                            double sample = channelData[frame];
                            sample *= volumeMultiplier;
                            // Clamp to prevent overflow
                            if (sample > 32767.0) sample = 32767.0;
                            if (sample < -32768.0) sample = -32768.0;
                            channelData[frame] = (SInt16)sample;
                        }
                    }
                }
            }
            break;
        }
        case AVAudioPCMFormatInt32: {
            if (buffer.format.isInterleaved) {
                // Interleaved format
                SInt32* data = buffer.int32ChannelData[0];
                for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                    for (UInt32 ch = 0; ch < channelCount; ch++) {
                        double sample = data[frame * channelCount + ch];
                        sample *= volumeMultiplier;
                        // Clamp to prevent overflow
                        if (sample > 2147483647.0) sample = 2147483647.0;
                        if (sample < -2147483648.0) sample = -2147483648.0;
                        data[frame * channelCount + ch] = (SInt32)sample;
                    }
                }
            } else {
                // Non-interleaved format
                for (UInt32 ch = 0; ch < channelCount; ch++) {
                    SInt32* channelData = buffer.int32ChannelData[ch];
                    if (channelData) {
                        for (AVAudioFrameCount frame = 0; frame < frameCount; frame++) {
                            double sample = channelData[frame];
                            sample *= volumeMultiplier;
                            // Clamp to prevent overflow
                            if (sample > 2147483647.0) sample = 2147483647.0;
                            if (sample < -2147483648.0) sample = -2147483648.0;
                            channelData[frame] = (SInt32)sample;
                        }
                    }
                }
            }
            break;
        }
        default:
            // Unsupported format, log warning
            if (self.verbose) {
                SecureLogf(@"Volume adjustment not supported for format: %d", (int)buffer.format.commonFormat);
            }
            break;
    }
}

@end

NS_ASSUME_NONNULL_END
