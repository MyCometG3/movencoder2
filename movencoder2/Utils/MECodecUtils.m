//
//  MECodecUtils.m
//  movencoder2
//
//  Created for refactoring on 2026/02/09.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "MECodecUtils.h"

NS_ASSUME_NONNULL_BEGIN

/* =================================================================================== */
// MARK: - Helper Functions
/* =================================================================================== */

// Helper function to safely read 24-bit pattern from big-endian buffer
static inline uint32_t read_be24_pattern(const uint8_t *p, const uint8_t *pEnd) {
    // need at least 3 bytes to form a 24-bit pattern
    if (p + 2 < pEnd) {
        return ((uint32_t)p[0] << 16) | ((uint32_t)p[1] << 8) | (uint32_t)p[2];
    } else {
        return 0xFFFFFF; // return invalid pattern when insufficient data
    }
}

static NSData* payload2NALs(NSArray *payloadArray) {
    if (payloadArray && [payloadArray count]) {
        const uint8_t startcode[4] = {0x00, 0x00, 0x00, 0x01};
        NSMutableData * nals = [NSMutableData data];
        for (NSData *payload in payloadArray) {
            [nals appendBytes:startcode length:4];
            [nals appendData:payload];
        }
        return nals;
    } else {
        return nil;
    }
}

/* =================================================================================== */
// MARK: - H.264/H.265 Codec Support Functions
/* =================================================================================== */

CMFormatDescriptionRef createDescriptionH264(AVCodecContext* avctx) {
    CMFormatDescriptionRef desc = NULL;
    
    if (!(avctx->extradata && avctx->extradata_size))
        return NULL;
    
    // gather sps/pps payload
    NSMutableArray* sps = [NSMutableArray array];
    NSMutableArray* pps = [NSMutableArray array];
    NSMutableArray* ext = [NSMutableArray array];
    {
        uint8_t *p = avctx->extradata;
        uint8_t *pEnd = p + avctx->extradata_size;
        uint8_t *nalPtr = NULL;
        size_t nalSize = 0;
        while (p < pEnd) {
            uint32_t pattern = read_be24_pattern(p, pEnd);
            if ((nalPtr && nalSize == 0)) {
                if ((pattern == 0x000001) || (pattern == 0x000000)) {
                    nalSize = (p - nalPtr);
                } else if (p+4 >= pEnd) {
                    nalSize = (pEnd - nalPtr);
                }
                if (nalPtr && nalSize > 0) {
                    uint8_t nal_type = nalPtr[0] & 0x1f;
                    if (nal_type == 7) {
                        [sps addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                    } else if (nal_type == 8) {
                        [pps addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                    } else if (nal_type == 13) {
                        [ext addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                    }
                    nalPtr = NULL;
                    nalSize = 0;
                    continue;
                }
            }
            if (pattern == 0x000001) {
                p += 3;
                nalPtr = p;     // update pointer to next nal payload
                nalSize = 0;    // reset nal size
            } else {
                p++;
            }
        }
    }
    
    if ([sps count] * [pps count] > 0) {
        // put SPS/PPS payload into NALs stream (with 4-byte start codes for internal concatenation)
        NSData *spsNALs = payload2NALs(sps);
        NSData *ppsNALs = payload2NALs(pps);
        NSData *extNALs = payload2NALs(ext);
        
        // Helper to strip 4-byte start code
        void (^strip4)(NSData* data, const uint8_t** outPtr, size_t* outSize) = ^(NSData* data, const uint8_t** outPtr, size_t* outSize) {
            if (!data) { *outPtr = NULL; *outSize = 0; return; }
            size_t len = data.length;
            if (len <= 4) { *outPtr = NULL; *outSize = 0; return; }
            *outPtr = ((const uint8_t*)data.bytes) + 4;
            *outSize = len - 4;
        };
        
        // create VideoFormatDescription using NALs stream (without start codes)
        if (extNALs.length > 0) {
            int numPS = 3;
            const uint8_t* paramSetPtr[3] = { NULL, NULL, NULL };
            size_t paramSetSize[3] = { 0, 0, 0 };
            strip4(spsNALs, &paramSetPtr[0], &paramSetSize[0]);
            strip4(ppsNALs, &paramSetPtr[1], &paramSetSize[1]);
            strip4(extNALs, &paramSetPtr[2], &paramSetSize[2]);
            if (paramSetPtr[0] && paramSetPtr[1]) {
                int nalUnitHeaderLength = 4;
                CMFormatDescriptionRef formatDescription = NULL;
                OSStatus err = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                                   numPS,
                                                                                   paramSetPtr,
                                                                                   paramSetSize,
                                                                                   nalUnitHeaderLength,
                                                                                   &formatDescription);
                if (err == noErr && formatDescription) {
                    desc = formatDescription;
                }
            }
        } else {
            int numPS = 2;
            const uint8_t* paramSetPtr[2] = { NULL, NULL };
            size_t paramSetSize[2] = { 0, 0 };
            strip4(spsNALs, &paramSetPtr[0], &paramSetSize[0]);
            strip4(ppsNALs, &paramSetPtr[1], &paramSetSize[1]);
            if (paramSetPtr[0] && paramSetPtr[1]) {
                int nalUnitHeaderLength = 4;
                CMFormatDescriptionRef formatDescription = NULL;
                OSStatus err = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                                   numPS,
                                                                                   paramSetPtr,
                                                                                   paramSetSize,
                                                                                   nalUnitHeaderLength,
                                                                                   &formatDescription);
                if (err == noErr && formatDescription) {
                    desc = formatDescription;
                }
            }
        }
    }
    
    return desc;
}

CMFormatDescriptionRef createDescriptionH265(AVCodecContext* avctx) {
    CMFormatDescriptionRef desc = NULL;
    
    if (!(avctx->extradata && avctx->extradata_size))
        return NULL;
    
    // gather vps/sps/pps payload
    NSMutableArray* vps = [NSMutableArray array];
    NSMutableArray* sps = [NSMutableArray array];
    NSMutableArray* pps = [NSMutableArray array];
    NSMutableArray* seipre = [NSMutableArray array];
    NSMutableArray* seisuf = [NSMutableArray array];
    {
        uint8_t *p = avctx->extradata;
        uint8_t *pEnd = p + avctx->extradata_size;
        uint8_t *nalPtr = NULL;
        size_t nalSize = 0;
        while (p < pEnd) {
            uint32_t pattern = read_be24_pattern(p, pEnd);
            if ((nalPtr && nalSize == 0)) {
                if ((pattern == 0x000001) || (pattern == 0x000000)) {
                    nalSize = (p - nalPtr);
                } else if (p+4 >= pEnd) {
                    nalSize = (pEnd - nalPtr);
                }
            }
            if (nalPtr && nalSize > 0) {
                uint8_t nal_type = nalPtr[0] & 0x3f;
                if (nal_type == 32) {
                    [vps addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                } else if (nal_type == 33) {
                    [sps addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                } else if (nal_type == 34) {
                    [pps addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                } else if (nal_type == 39) {
                    [seipre addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                } else if (nal_type == 40) {
                    [seisuf addObject:[NSData dataWithBytesNoCopy:nalPtr length:nalSize freeWhenDone:FALSE]];
                }
            }
            if (pattern == 0x000001) {
                p += 3;
                nalPtr = p;     // update pointer to next nal payload
                nalSize = 0;    // reset nal size
            } else {
                p++;
            }
        }
    }
    
    if ([vps count] * [sps count] * [pps count]) {
        // put payload into NALs stream (with 4-byte start codes internally)
        NSData *vpsNALs = payload2NALs(vps);
        NSData *spsNALs = payload2NALs(sps);
        NSData *ppsNALs = payload2NALs(pps);
        NSData *seipreNALs = payload2NALs(seipre);
        NSData *seisufNALs = payload2NALs(seisuf);
        
        // Helper to strip 4-byte start code
        void (^strip4)(NSData* data, const uint8_t** outPtr, size_t* outSize) = ^(NSData* data, const uint8_t** outPtr, size_t* outSize) {
            if (!data) { *outPtr = NULL; *outSize = 0; return; }
            size_t len = data.length;
            if (len <= 4) { *outPtr = NULL; *outSize = 0; return; }
            *outPtr = ((const uint8_t*)data.bytes) + 4;
            *outSize = len - 4;
        };
        
        int numPS = 3;
        const uint8_t* paramSetPtr[5] = { NULL, NULL, NULL, NULL, NULL };
        size_t paramSetSize[5] = { 0, 0, 0, 0, 0 };
        strip4(vpsNALs, &paramSetPtr[0], &paramSetSize[0]);
        strip4(spsNALs, &paramSetPtr[1], &paramSetSize[1]);
        strip4(ppsNALs, &paramSetPtr[2], &paramSetSize[2]);
        if (seipreNALs.length > 4) { strip4(seipreNALs, &paramSetPtr[numPS], &paramSetSize[numPS]); if (paramSetPtr[numPS]) numPS++; }
        if (seisufNALs.length > 4) { strip4(seisufNALs, &paramSetPtr[numPS], &paramSetSize[numPS]); if (paramSetPtr[numPS]) numPS++; }
        
        if (paramSetPtr[0] && paramSetPtr[1] && paramSetPtr[2]) {
            int nalUnitHeaderLength = 4;
            CMFormatDescriptionRef formatDescription = NULL;
            OSStatus err = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                               numPS,
                                                                               paramSetPtr,
                                                                               paramSetSize,
                                                                               nalUnitHeaderLength,
                                                                               NULL,
                                                                               &formatDescription);
            if (err == noErr && formatDescription) {
                desc = formatDescription;
            }
        }
    }
    
    return desc;
}

CMFormatDescriptionRef createDescriptionWithAperture(CMFormatDescriptionRef inDesc, NSValue* cleanApertureValue) {
    if (cleanApertureValue) {
        // Prepare extensions dictionary
        CFDictionaryRef inExt = CMFormatDescriptionGetExtensions(inDesc);
        CFMutableDictionaryRef outExt = NULL;
        if (inExt) {
            outExt = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, inExt);
            CFDictionaryRemoveValue(outExt, kCMFormatDescriptionExtension_VerbatimSampleDescription);
            CFDictionaryRemoveValue(outExt, kCMFormatDescriptionExtension_VerbatimISOSampleEntry);
        } else {
            outExt = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                               &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        }
        
        // Set clap extension
        NSMutableDictionary *clap = [NSMutableDictionary dictionary];
        NSRect rect = cleanApertureValue.rectValue;
        int cWidth = rect.origin.x;
        int cHeight = rect.origin.y;
        int hOffset = rect.size.width;
        int vOffset = rect.size.height;
        clap[(__bridge NSString*)kCMFormatDescriptionKey_CleanApertureWidth] = @(cWidth);
        clap[(__bridge NSString*)kCMFormatDescriptionKey_CleanApertureHeight] = @(cHeight);
        clap[(__bridge NSString*)kCMFormatDescriptionKey_CleanApertureHorizontalOffset] = @(hOffset);
        clap[(__bridge NSString*)kCMFormatDescriptionKey_CleanApertureVerticalOffset] = @(vOffset);
        CFDictionarySetValue(outExt, kCMFormatDescriptionExtension_CleanAperture,
                             (__bridge CFDictionaryRef)clap);
        
        // Create new description
        CMVideoFormatDescriptionRef outDesc = NULL;
        CMVideoCodecType codec = CMFormatDescriptionGetMediaSubType(inDesc);
        CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(inDesc);
        
        CMVideoFormatDescriptionCreate(kCFAllocatorDefault, codec, dim.width, dim.height, outExt, &outDesc);
        CFRelease(outExt);
        if (outDesc) {
            return outDesc;
        }
    }
    
    return NULL;
}

NS_ASSUME_NONNULL_END
