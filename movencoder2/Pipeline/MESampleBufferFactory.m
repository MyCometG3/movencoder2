//
//  MESampleBufferFactory.m
//  movencoder2
//
//  Created by Copilot on 2025-09-29.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MESampleBufferFactory.h"
#import "MECommon.h"
#import "MEUtils.h"
#import "MESecureLogging.h"
#import "MEManager.h"
#import "Config/MEVideoEncoderConfig.h"

NS_ASSUME_NONNULL_BEGIN

static BOOL MENalTypeIsSync(uint8_t nalType, enum AVCodecID codecId)
{
    if (codecId == AV_CODEC_ID_H264) {
        return (nalType == 5);
    }
    if (codecId == AV_CODEC_ID_HEVC) {
        return (nalType >= 16 && nalType <= 21);
    }
    return NO;
}

static uint8_t MENalTypeForCodec(uint8_t header, enum AVCodecID codecId)
{
    if (codecId == AV_CODEC_ID_H264) {
        return header & 0x1F;
    }
    if (codecId == AV_CODEC_ID_HEVC) {
        return (header >> 1) & 0x3F;
    }
    return 0;
}

static BOOL MENalContainsSyncSample(const uint8_t *data, size_t size, enum AVCodecID codecId)
{
    if (!data || size < 1) {
        return NO;
    }
    if (codecId != AV_CODEC_ID_H264 && codecId != AV_CODEC_ID_HEVC) {
        return NO;
    }
    
    
    const uint8_t *p = data;
    const uint8_t *end = data + size;
    const uint8_t *nal_start = avc_find_startcode(p, end);
    while (nal_start < end) {
        while (nal_start < end && !*(nal_start++)) {
        }
        if (nal_start >= end) {
            break;
        }
        uint8_t nalType = MENalTypeForCodec(*nal_start, codecId);
        if (MENalTypeIsSync(nalType, codecId)) {
            return YES;
        }
        nal_start = avc_find_startcode(nal_start, end);
    }
    return NO;
}

static BOOL MEPacketIsSyncSample(const AVPacket *packet, enum AVCodecID codecId)
{
    if (!packet) {
        return NO;
    }
    if (packet->flags & AV_PKT_FLAG_KEY) {
        return YES;
    }
    if (codecId != AV_CODEC_ID_H264 && codecId != AV_CODEC_ID_HEVC) {
        return NO;
    }
    if (!packet->data || packet->size <= 0) {
        return NO;
    }
    return MENalContainsSyncSample(packet->data, (size_t)packet->size, codecId);
}

@implementation MESampleBufferFactory

@synthesize timeBase = _timeBase;
@synthesize formatDescription = _formatDescription;
@synthesize pixelBufferPool = _pixelBufferPool;
@synthesize pixelBufferAttachments = _pixelBufferAttachments;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _timeBase = 0;
        _formatDescription = NULL;
        _pixelBufferPool = NULL;
        _pixelBufferAttachments = NULL;
        _verbose = NO;
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    if (_formatDescription) {
        CFRelease(_formatDescription);
        _formatDescription = NULL;
    }
    if (_pixelBufferPool) {
        CFRelease(_pixelBufferPool);
        _pixelBufferPool = NULL;
    }
    if (_pixelBufferAttachments) {
        CFRelease(_pixelBufferAttachments);
        _pixelBufferAttachments = NULL;
    }
}

- (BOOL)isUsingVideoFilter
{
    // This would typically check for videoFilterString != NULL in the original MEManager
    // For now, we'll assume this is determined by the caller
    return NO; // Placeholder - would need to be set by the caller
}

- (BOOL)isUsingVideoEncoder
{
    return (self.videoEncoderSetting != NULL);
}

- (BOOL)isUsingLibx264WithConfig:(MEVideoEncoderConfig * _Nullable)config
{
    if (![self isUsingVideoEncoder]) return NO;
    return (config && config.codecKind == MEVideoCodecKindX264);
}

- (BOOL)isUsingLibx265WithConfig:(MEVideoEncoderConfig * _Nullable)config
{
    if (![self isUsingVideoEncoder]) return NO;
    return (config && config.codecKind == MEVideoCodecKindX265);
}

- (nullable CMSampleBufferRef)createUncompressedSampleBufferFromFilteredFrame:(void *)filteredFrame
{
    AVFrame *frame = (AVFrame *)filteredFrame;
    if (!frame) {
        SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Invalid filtered frame.");
        return NULL;
    }
    
    // From AVFrame to CMSampleBuffer(CVImageBuffer); Uncompressed
    CVPixelBufferRef pb = NULL;
    CMSampleBufferRef sb = NULL;
    OSStatus err = noErr;

    if (![self isUsingVideoFilter]) {
        SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Invalid state detected.");
        goto end;
    }
    
    // Create PixelBufferPool for uncompressed AVFrame
    if (frame && !_pixelBufferPool) {
        _pixelBufferPool = AVFrameCreateCVPixelBufferPool(frame);
        if (!_pixelBufferPool) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup CVPixelBufferPool.");
            goto end;
        }
    }
    
    // Create PixelBuffer Attachments dictionary
    if (frame && !_pixelBufferAttachments) {
        _pixelBufferAttachments = AVFrameCreateCVBufferAttachments(frame);
        if (!_pixelBufferAttachments) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup CVBufferAttachments.");
            goto end;
        }
    }
    
    // Create new PixelBuffer for uncompressed AVFrame
    if (frame && _pixelBufferPool) {
        pb = AVFrameCreateCVPixelBuffer(frame, _pixelBufferPool);
        if (!pb) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup CVPixelBuffer.");
            goto end;
        }
    }
    
    // Fill PixelBuffer attachments using properties of filtered AVFrame
    if (pb && _pixelBufferAttachments) {
        CVBufferSetAttachments(pb, _pixelBufferAttachments, kCVAttachmentMode_ShouldPropagate);
    }
    
    // Create formatDescription for PixelBuffer
    if (pb && !_formatDescription) {
        CMVideoFormatDescriptionRef descForPB = NULL;
        err = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,
                                                           pb,
                                                           &descForPB);
        if (err || !descForPB) {
            goto end;
        }
        _formatDescription = descForPB;
    }
    
    if (pb && _formatDescription && _timeBase) {
        CMSampleBufferRef sbForPB = NULL;
        CMSampleTimingInfo info = {
            kCMTimeInvalid,
            CMTimeMake(frame->pts, _timeBase),
            CMTimeMake(frame->pkt_dts, _timeBase)
        };
        err = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                       pb,
                                                       _formatDescription,
                                                       &info,
                                                       &sbForPB);
        if (err || !sbForPB) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup uncompressed CMSampleBuffer.");
            goto end;
        }
        sb = sbForPB;
        
        CVPixelBufferRelease(pb);
        return sb;
    }
    
end:
    if (pb) {
        CVPixelBufferRelease(pb);
    }
    return NULL;
}

- (nullable CMSampleBufferRef)createCompressedSampleBufferFromPacket:(void *)encodedPacket 
                                                         codecContext:(void *)codecContext
                                                   videoEncoderConfig:(MEVideoEncoderConfig * _Nullable)videoEncoderConfig
{
    AVPacket *packet = (AVPacket *)encodedPacket;
    AVCodecContext *avctx = (AVCodecContext *)codecContext;
    
    if (!packet || !avctx) {
        SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Invalid packet or codec context.");
        return NULL;
    }
    
    if (![self isUsingVideoEncoder]) {
        SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Invalid state detected.");
        goto end;
    }
    
    if (!_formatDescription) {
        if ([self isUsingLibx264WithConfig:videoEncoderConfig]) {
            _formatDescription = createDescriptionH264(avctx);
        } else if ([self isUsingLibx265WithConfig:videoEncoderConfig]) {
            _formatDescription = createDescriptionH265(avctx);
        }
        if (!_formatDescription) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup CMVideoFormatDescription.");
            goto end;
        }
        
        // Append container level clean aperture
        NSValue *cleanApertureValue = videoEncoderConfig.cleanAperture ?: self.videoEncoderSetting[kMEVECleanApertureKey];
        if (cleanApertureValue) {
            CMVideoFormatDescriptionRef newDesc = createDescriptionWithAperture(_formatDescription, cleanApertureValue);
            if (newDesc) {
                CFRelease(_formatDescription);
                _formatDescription = newDesc;
            } else {
                SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Failed to create CMVideoFormatDescription with clean aperture. Keeping original format description.");
            }
        }
        if (!_formatDescription) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup CMVideoFormatDescription with clean aperture.");
            goto end;
        }
    }
    
    // From AVPacket to CMSampleBuffer(CMBLockBuffer); Compressed
    if (_formatDescription && _timeBase) {
        enum AVCodecID codecId = avctx ? avctx->codec_id : AV_CODEC_ID_NONE;
        BOOL isSyncSample = MEPacketIsSyncSample(packet, codecId);
        // Get temp NAL buffer
        int tempSize = packet->size;
        UInt8* tempPtr = av_malloc(tempSize);
        if (!tempPtr) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Failed to allocate %d bytes for NAL processing", tempSize);
            goto end;
        }
        
        // Re-format NAL unit with bounds checking
        if (tempSize > 0 && packet->data) {
            memcpy(tempPtr, packet->data, tempSize);
            avc_parse_nal_units(&tempPtr, &tempSize);    // This call frees original buffer and allocates new one
        } else {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Invalid data for NAL processing: tempSize=%d, packet->data=%p",
                  tempSize, packet->data);
            av_free(tempPtr);
            goto end;
        }
        
        // Create CMBlockBuffer
        OSStatus err = noErr;
        CMBlockBufferRef bb = NULL;
        err = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,   // allocator of CMBlockBuffer
                                                 NULL,                  // allocate new memoryBlock
                                                 tempSize,              // requested size of memoryBlock
                                                 kCFAllocatorDefault,   // allocator of memoryBlock
                                                 NULL,                  // No custom block source
                                                 0,                     // offset to data in memoryBlock
                                                 tempSize,              // length of data in memoryBlock
                                                 kCMBlockBufferAssureMemoryNowFlag,
                                                 &bb);
        if (err) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup CMBlockBuffer.");
            av_free(tempPtr);
            goto end;
        }
        
        // Copy NAL buffer into CMBlockBuffer
        err = CMBlockBufferReplaceDataBytes(tempPtr,                    // Data source pointer
                                            bb,                         // target CMBlockBuffer
                                            0,                          // replacing offset of target memoryBlock
                                            tempSize);                  // replacing size of data written from offset
        av_free(tempPtr);
        if (err) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup CMBlockBuffer.");
            if (bb) CFRelease(bb);
            goto end;
        }
        
        // Create CMSampleBuffer from CMBlockBuffer
        CMItemCount numSamples = 1;
        CMSampleTimingInfo info = {
            kCMTimeInvalid,
            CMTimeMake(packet->pts, _timeBase),
            CMTimeMake(packet->dts, _timeBase)
        };
        CMSampleTimingInfo sampleTimingArray[1] = { info };
        CMItemCount numSampleTimingEntries = 1;
        size_t sampleSizeArray[1] = { tempSize };
        CMItemCount numSampleSizeEntries = 1;
        CMSampleBufferRef sb = NULL;
        err = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                        bb,
                                        _formatDescription,
                                        numSamples,
                                        numSampleTimingEntries,
                                        sampleTimingArray,
                                        numSampleSizeEntries,
                                        sampleSizeArray,
                                        &sb);
        if (bb) CFRelease(bb);
        if (err) {
            SecureErrorLogf(@"[MESampleBufferFactory] ERROR: Cannot setup compressed CMSampleBuffer.");
            goto end;
        }
        
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sb, true);
        if (attachments && CFArrayGetCount(attachments) > 0) {
            CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            if (dict) {
                CFDictionarySetValue(dict,
                                     kCMSampleAttachmentKey_NotSync,
                                     isSyncSample ? kCFBooleanFalse : kCFBooleanTrue);
            }
        }
        
        return sb;
    }
    
end:
    return NULL;
}

- (void)resetFormatDescription
{
    if (_formatDescription) {
        CFRelease(_formatDescription);
        _formatDescription = NULL;
    }
}

- (void)resetPixelBufferPool
{
    if (_pixelBufferPool) {
        CFRelease(_pixelBufferPool);
        _pixelBufferPool = NULL;
    }
    if (_pixelBufferAttachments) {
        CFRelease(_pixelBufferAttachments);
        _pixelBufferAttachments = NULL;
    }
}

@end

NS_ASSUME_NONNULL_END
