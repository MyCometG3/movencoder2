//
//  METranscoder+CompressionSettings.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#import "METranscoder+Internal.h"
#import "MESecureLogging.h"

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

NS_ASSUME_NONNULL_BEGIN

@implementation METranscoder (CompressionSettings)

- (BOOL) hasFieldModeSupportOf:(AVMovieTrack*)track
{
    BOOL result = FALSE;
    NSArray* descArray = track.formatDescriptions;
    
    CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef) descArray[0];
    CFDictionaryRef dict = NULL;
    VTDecompressionSessionRef decompSession = NULL;
    {
        OSStatus status = noErr;
        CFDictionaryRef spec = NULL;
        status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                              desc,
                                              spec,
                                              NULL,
                                              NULL,
                                              &decompSession);
        if (status != noErr) return FALSE;
        
        status = VTSessionCopySupportedPropertyDictionary(decompSession, &dict);
        
        if (status != noErr) goto end;
        
        if (dict) {
            CFDictionaryRef propFieldMode = CFDictionaryGetValue(dict, kVTDecompressionPropertyKey_FieldMode);
            if (propFieldMode) {
                CFArrayRef propList = CFDictionaryGetValue(propFieldMode, kVTPropertySupportedValueListKey);
                if (propList) {
                    result = CFArrayContainsValue(propList,
                                                  CFRangeMake(0, CFArrayGetCount(propList)),
                                                  kVTDecompressionProperty_FieldMode_BothFields);
                }
            }
            CFRelease(dict);
        }
    }

end:
    if (decompSession) {
        VTDecompressionSessionInvalidate(decompSession);
        CFRelease(decompSession);
    }
    return result;
}

- (void) addDecommpressionPropertiesOf:(AVMovieTrack*)track setting:(NSMutableDictionary*)arOutputSetting
{
    if ([self hasFieldModeSupportOf:track]) {
        NSDictionary* decompressionProperties = nil;
        
        // Keep both fields
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        dict[(__bridge NSString*)kVTDecompressionPropertyKey_FieldMode] = (__bridge NSString*)kVTDecompressionProperty_FieldMode_BothFields;
        decompressionProperties = [dict copy];
        
        // TODO: kVTDecompressionPropertyKey_PixelTransferProperties

        arOutputSetting[AVVideoDecompressionPropertiesKey] = decompressionProperties;
    }
}

- (NSMutableDictionary<NSString*,id>*)videoCompressionSettingFor:(AVMovieTrack *)track
{
    //
    NSDictionary* compressionProperties = nil;
    NSArray* proresFamily = @[@"ap4h", @"apch", @"apcn", @"apcs", @"apco"];
    if ([proresFamily containsObject:self.videoFourcc]) {
        // ProRes family
    } else {
        compressionProperties = @{AVVideoAverageBitRateKey:@(self.videoBitRate)};
    }
    
    NSDictionary* cleanAperture = nil;
    NSDictionary* pixelAspectRatio = nil;
    NSDictionary* nclc = nil;
    
    CGSize trackDimensions = track.naturalSize;
    NSArray* descArray = track.formatDescriptions;
    if (descArray.count > 0) {
        CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)(descArray[0]);
        trackDimensions = CMVideoFormatDescriptionGetPresentationDimensions(desc, FALSE, FALSE);
        
        NSNumber* fieldCount = nil;
        NSString* fieldDetail = nil;
        
        CFPropertyListRef cfExtCA = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_CleanAperture);
        if (cfExtCA != NULL) {
            NSDictionary* extCA = (__bridge NSDictionary*)cfExtCA;
            NSNumber* width = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureWidth];
            NSNumber* height = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureHeight];
            NSNumber* hOffset = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureHorizontalOffset];
            NSNumber* vOffset = (NSNumber*)extCA[(__bridge  NSString*)kCMFormatDescriptionKey_CleanApertureVerticalOffset];
            
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            dict[AVVideoCleanApertureWidthKey] = width;
            dict[AVVideoCleanApertureHeightKey] = height;
            dict[AVVideoCleanApertureHorizontalOffsetKey] = hOffset;
            dict[AVVideoCleanApertureVerticalOffsetKey] = vOffset;
            
            cleanAperture = dict;
        }
        
        CFPropertyListRef cfExtPA = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_PixelAspectRatio);
        if (cfExtPA != NULL) {
            NSDictionary* extPA = (__bridge NSDictionary*)cfExtPA;
            NSNumber* hSpacing = (NSNumber*)extPA[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing];
            NSNumber* vSpacing = (NSNumber*)extPA[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing];
            
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            dict[AVVideoPixelAspectRatioHorizontalSpacingKey] = hSpacing;
            dict[AVVideoPixelAspectRatioVerticalSpacingKey] = vSpacing;
            
            pixelAspectRatio = dict;
        }
        
        if (self.copyNCLC) {
            CFPropertyListRef cfExtCP = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_ColorPrimaries);
            CFPropertyListRef cfExtTF = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_TransferFunction);
            CFPropertyListRef cfExtMX = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_YCbCrMatrix);
            if (cfExtCP && cfExtTF && cfExtMX) {
                NSString* colorPrimaries = (__bridge NSString*) cfExtCP;
                NSString* transferFunction = (__bridge NSString*) cfExtTF;
                NSString* ycbcrMatrix = (__bridge NSString*) cfExtMX;
                
                NSMutableDictionary* dict = [NSMutableDictionary dictionary];
                dict[AVVideoColorPrimariesKey] = colorPrimaries;
                dict[AVVideoTransferFunctionKey] = transferFunction;
                dict[AVVideoYCbCrMatrixKey] = ycbcrMatrix;
                
                nclc = dict;
            }
        }
        
        if (self.copyField) {
            CFPropertyListRef cfExtFC = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldCount);
            CFPropertyListRef cfExtFD = CMFormatDescriptionGetExtension(desc, kCMFormatDescriptionExtension_FieldDetail);
            if (cfExtFC && cfExtFD) {
                fieldCount = (__bridge NSNumber*)cfExtFC;
                fieldDetail = (__bridge NSString*)cfExtFD;
            }
        }
        
        if (fieldCount || fieldDetail) {
            NSMutableDictionary* dict = [NSMutableDictionary dictionary];
            
            if (self.copyField && fieldCount && fieldDetail) {
                dict[(__bridge NSString*)kVTCompressionPropertyKey_FieldCount] = fieldCount;
                dict[(__bridge NSString*)kVTCompressionPropertyKey_FieldDetail] = fieldDetail;
            }
            
            if (compressionProperties) {
                [dict addEntriesFromDictionary:compressionProperties];
            }
            compressionProperties = dict;
        }
    }
    
    // destination
    NSMutableDictionary* awInputSetting = [NSMutableDictionary dictionary];
    awInputSetting[AVVideoCodecKey] = self.videoFourcc;
    awInputSetting[AVVideoWidthKey] = @(trackDimensions.width);
    awInputSetting[AVVideoHeightKey] = @(trackDimensions.height);
    if (compressionProperties) {
        awInputSetting[AVVideoCompressionPropertiesKey] = compressionProperties;
    }
    
    if (cleanAperture) {
        awInputSetting[AVVideoCleanApertureKey] = cleanAperture;
    }
    if (pixelAspectRatio) {
        awInputSetting[AVVideoPixelAspectRatioKey] = pixelAspectRatio;
    }
    if (nclc) {
        awInputSetting[AVVideoColorPropertiesKey] = nclc;
    }
    return awInputSetting;
}

@end

NS_ASSUME_NONNULL_END
