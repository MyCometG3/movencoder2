//
//  main.m
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//  Copyright © 2018-2025 MyCometG3. All rights reserved.
//

/*
 * This file is part of movencoder2.
 *
 * movencoder2 is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * movencoder2 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with movencoder2; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 */

@import Foundation;

#import "MECommon.h"
#import "parseUtil.h"
#import "monitorUtil.h"
#import "METranscoder.h"
#import "MEManager.h"
#import "MEAudioConverter.h"
#import <getopt.h>

NS_ASSUME_NONNULL_BEGIN

#if 1
float initialDelayInSec = 0.1;
#else
float initialDelayInSec = 5.0;
#endif

/* =================================================================================== */
// MARK: - option parse function
/* =================================================================================== */

/*
 # -meve "options"
 #     c=_; video codec name of ffmpeg (i.e. libx264, libx265, ...)
 #     o=_; video codec options of ffmpeg
 #  x264=_; libx264 specific option string
 #  x265=_; libx265 specific option string
 #     r=_; video frame rate (i.e. 24, 29.97, 30, 59.94, 60, ...) ***
 #  size=_; pixel resolution width:height (i.e. 720:480)
 #   par=_; pixel aspect ratio (i.e. 10:11, 1:1, ...)
 #     f=_; libavfilter string
 #     b=_; video codec bitrate
 # clean=_; clean aperture rectangle w,h,vo,ho (i.e. 704,472,0,0)
 # *** NO resample support yet. Used for rate control only.
 */
static BOOL parseOptMEVE(NSString* param, MEManager* manager) {
    NSMutableDictionary* videoEncoderSetting = [NSMutableDictionary new];
    NSString* filterString = nil;
    NSArray* optArray = [param componentsSeparatedByString:separator];
    for (NSString* opt in optArray) {
        NSArray* optParse = [opt componentsSeparatedByString:equal];
        NSString* key = optParse[0];
        NSString* val = optParse[1];
        if (optParse.count > 2) {
            // parsing "param=mode=1" => key:"param", val:"mode=1"
            NSMutableArray* optParse2 = [optParse mutableCopy];
            [optParse2 removeObjectAtIndex:0];
            val = [optParse2 componentsJoinedByString:equal];
        }
        if ([key isEqualToString:@"c"]) {
            if (nil == val) goto error;
            videoEncoderSetting[kMEVECodecNameKey] = val; // NSString
        }
        if ([key isEqualToString:@"o"]) {
            if (nil == val) goto error;
            NSDictionary *codecOptions = parseCodecOptions(val);
            if (codecOptions.allKeys.count == 0) goto error;
            videoEncoderSetting[kMEVECodecOptionsKey] = codecOptions; // NSDictionary
        }
        if ([key isEqualToString:@"x264"]) {
            if (nil == val) goto error;
            videoEncoderSetting[kMEVEx264_paramsKey] = val; // NSString
        }
        if ([key isEqualToString:@"x265"]) {
            if (nil == val) goto error;
            videoEncoderSetting[kMEVEx265_paramsKey] = val; // NSString
        }
        if ([key isEqualToString:@"r"]) {
            if (nil == val) goto error;
            NSValue* timeValue = parseTime(val);
            if (nil == timeValue) goto error;
            videoEncoderSetting[kMEVECodecFrameRateKey] = timeValue; // NSValue of CMTime
        }
        if ([key isEqualToString:@"size"]) {
            if (nil == val) goto error;
            NSValue* sizeValue = parseSize(val);
            if (nil == sizeValue) goto error;
            videoEncoderSetting[kMEVECodecWxHKey] = sizeValue; // NSValue of NSSize
        }
        if ([key isEqualToString:@"par"]) {
            if (nil == val) goto error;
            NSValue* sizeValue = parseSize(val);
            if (nil == sizeValue) goto error;
            videoEncoderSetting[kMEVECodecPARKey] = sizeValue; // NSValue of NSSize
        }
        if ([key isEqualToString:@"f"]) {
            if (nil == val) goto error;
            // videoEncoderSetting[MEVideoFilter_FilterStringKey] = val; // NSString
            filterString = val;
        }
        if ([key isEqualToString:@"b"]) {
            if (nil == val) goto error;
            NSNumber *doubleNumber = parseDouble(val);
            videoEncoderSetting[kMEVECodecBitRateKey] = doubleNumber;
        }
        if ([key isEqualToString:@"clean"]) {
            if (nil == val) goto error;
            NSValue* rectValue = parseRect(val);
            if (nil == rectValue) goto error;
            videoEncoderSetting[kMEVECleanApertureKey] = rectValue; // NSValue of NSRect;
        }
    }
    
    if (videoEncoderSetting.count > 0)
        manager.videoEncoderSetting = [videoEncoderSetting mutableCopy];
    if (filterString)
        manager.videoFilterString = [filterString mutableCopy];
    return TRUE;
    
error:
    return FALSE;
}

/*
 # -ve "options" (or -v "options")
 # bitrate=_; video bit rate (i.e. 2.5M, 5M, 10M, 20M, ...)
 #   field=_; keep filedmode flag (yes, no)
 #    nclc=_; keep nclc flag (yes, no)
 #  encode=_; transcode video using AVFoundation (yes, no)
 #   codec=_; fourcc of video codec (avc1, hvc1, apcn, apcs, apco, ...)
 */
static BOOL parseOptVE(NSString* param, METranscoder* coder) {
    NSArray* optArray = [param componentsSeparatedByString:separator];
    for (NSString* opt in optArray) {
        NSArray* optParse = [opt componentsSeparatedByString:equal];
        NSString* key = optParse[0];
        NSString* val = optParse[1];
        if ([key isEqualToString:@"bitrate"]) {
            if (nil == val) goto error;
            NSNumber* bpsNum = parseDouble(val);
            if (nil == bpsNum) goto error;
            coder.param[kVideoKbpsKey] = @(bpsNum.doubleValue / 1000.0);
        }
        if ([key isEqualToString:@"field"]) {
            if (nil == val) goto error;
            NSNumber* copyFieldNum = parseBool(val);
            if (nil == copyFieldNum) goto error;
            coder.param[kCopyFieldKey] = copyFieldNum;
        }
        if ([key isEqualToString:@"nclc"]) {
            if (nil == val) goto error;
            NSNumber* copyNCLCNum = parseBool(val);
            if (nil == copyNCLCNum) goto error;
            coder.param[kCopyNCLCKey] = copyNCLCNum;
        }
        if ([key isEqualToString:@"encode"]) {
            if (nil ==  val) goto error;
            NSNumber* videoEncodeNum = parseBool(val);
            if (nil == videoEncodeNum) goto error;
            coder.param[kVideoEncodeKey] = videoEncodeNum;
        }
        if ([key isEqualToString:@"codec"]) {
            if (!val) goto error;
            val = [val stringByPaddingToLength:4 withString:@" " startingAtIndex:0];
            coder.param[kVideoCodecKey] = val;
        }
    }
    
    return TRUE;
    
error:
    return FALSE;
}

/*
 # -ae "options" (or -a "options")
 #   depth=_; LPCM bit depth (8, 16, 32)
 # bitrate=_; audio bit rate (i.e. 96k, 128k, 192k, ...)
 #  encode=_; transcode audio using AVFoundation (yes, no)
 #   codec=_; fourcc of audio codec (lcpm, aac, alac, ...)
 #  layout=_; Audio channel layout tag (integer or AAC layout name, e.g. Stereo, AAC_5_1, 100)
 #  volume=_; gain/volume control in dB (e.g. +3.0, -1.5, 0.0, range: -10.0 to +10.0)
 */
static BOOL parseOptAE(NSString* param, METranscoder* coder) {
    NSArray* optArray = [param componentsSeparatedByString:separator];
    for (NSString* opt in optArray) {
        NSArray* optParse = [opt componentsSeparatedByString:equal];
        NSString* key = optParse[0];
        NSString* val = optParse[1];
        if ([key isEqualToString:@"depth"]) {
            if (nil == val) goto error;
            NSNumber* depthNum = parseInteger(val);
            if (nil == depthNum) goto error;
            coder.param[kLPCMDepthKey] = depthNum;
        }
        if ([key isEqualToString:@"bitrate"]) {
            if (nil == val) goto error;
            NSNumber* bpsNum = parseDouble(val);
            if (nil == bpsNum) goto error;
            coder.param[kAudioKbpsKey] = @(bpsNum.doubleValue / 1000);
        }
        if ([key isEqualToString:@"encode"]) {
            if (nil == val) goto error;
            NSNumber* audioEncodeNum = parseBool(val);
            if (nil == audioEncodeNum) goto error;
            coder.param[kAudioEncodeKey] = audioEncodeNum;
        }
        if ([key isEqualToString:@"codec"]) {
            if (nil == val) goto error;
            val = [val stringByPaddingToLength:4 withString:@" " startingAtIndex:0];
            coder.param[kAudioCodecKey] = val;
        }
        // Parse layoutTag (supports both integer and AAC layout name)
        if ([key isEqualToString:@"layout"]) {
            if (nil == val) goto error;
            NSNumber* layoutTagNum = parseLayoutTag(val);
            if (nil == layoutTagNum) goto error;
            coder.param[kAudioChannelLayoutTagKey] = layoutTagNum;
        }
        // Parse volume/gain in dB (range: -10.0 to +10.0)
        if ([key isEqualToString:@"volume"]) {
            if (nil == val) goto error;
            NSNumber* volumeNum = parseDouble(val);
            if (nil == volumeNum) goto error;
            double volumeDb = volumeNum.doubleValue;
            if (volumeDb < -10.0 || volumeDb > 10.0) {
                NSLog(@"ERROR: volume parameter out of range (-10.0 to +10.0 dB): %f", volumeDb);
                goto error;
            }
            coder.param[kAudioVolumeKey] = volumeNum;
        }
    }
    
    return TRUE;
    
error:
    return FALSE;
}

/*
 ### MEManager.h
 extern NSString* const kMEVECodecNameKey;       // ffmpeg -c:v libx264
 extern NSString* const kMEVECodecOptionsKey;    // NSDictionary of AVOptions for codec ; ffmpeg -h encoder=libx264
 extern NSString* const kMEVEx264_paramsKey;     // NSString ; ffmpeg -x264-params "x264option_strings"
 extern NSString* const kMEVEx265_paramsKey;     // NSString ; ffmpeg -x265-params "x265option_strings"
 extern NSString* const kMEVECodecFrameRateKey;  // NSValue of CMTime ; ffmpeg -r 30000:1001
 extern NSString* const kMEVECodecWxHKey;        // NSValue of NSSize ; ffmpeg -s 720x480
 extern NSString* const kMEVECodecPARKey;        // NSValue of NSSize ; ffmpeg -aspect 16:9
 extern NSString* const kMEVFFilterStringKey;    // NSString ; ffmpeg -vf "filter_graph_strings"
 extern NSString* const kMEVECodecBitRateKey;    // NSNumber ; ffmpeg -b:v 2.5M
 extern NSString* const kMEVECleanApertureKey;   // NSValue of NSRect ; convert as ffmpeg -crop-left/right/top/bottom

 ### METranscoder.h
 extern NSString* const kLPCMDepthKey;       // NSNumber of int
 extern NSString* const kAudioKbpsKey;       // NSNumber of float
 extern NSString* const kVideoKbpsKey;       // NSNumber of float
 extern NSString* const kCopyFieldKey;       // NSNumber of BOOL
 extern NSString* const kCopyNCLCKey;        // NSNumber of BOOL
 extern NSString* const kCopyOtherMediaKey;  // NSNumber of BOOL
 extern NSString* const kVideoEncodeKey;     // NSNumber of BOOL
 extern NSString* const kAudioEncodeKey;     // NSNumber of BOOL
 extern NSString* const kVideoCodecKey;      // NSString representation of OSType
 extern NSString* const kAudioCodecKey;      // NSString representation of OSType
 */

static METranscoder* validateOpt(int argc, char * const * argv) {
    BOOL verbose = FALSE;
    BOOL dump = FALSE;
    BOOL debug = FALSE;
    NSURL* input = nil;
    NSURL* output = nil;
    NSString* meve = nil;
    NSString* mevf = nil;
    NSString* mex264 = nil;
    NSString* mex265 = nil;
    NSString* ve = nil;
    NSString* ae = nil;
    NSString* co = nil;
    
    METranscoder* transcoder = nil;
    NSArray *videoTracks = nil;
    NSArray *audioTracks = nil;
    
    const char* shortopts = "V:D:d:i:o:v:a:c";
    static struct option longopts[] = {
        {"verbose", no_argument, NULL, 'V'},
        {"dump", no_argument, NULL, 'D'},
        {"debug", no_argument, NULL, 'd'},
        {"in", required_argument, NULL, 'i'},
        {"out", required_argument, NULL, 'o'},
        {"ve", required_argument, NULL, 'v'},
        {"ae", required_argument, NULL, 'a'},
        {"co", no_argument, NULL, 'c'},
        {"meve", required_argument, NULL, -128},
        {"mevf", required_argument, NULL, -129},
        {"mex264", required_argument, NULL, -264},
        {"mex265", required_argument, NULL, -265},
        {0,0,0,0}
    };
    
    int opt, longindex;
    opterr = 0;
    while ((opt = getopt_long_only(argc, argv, shortopts, longopts, &longindex)) != -1) {
        NSString* val = optarg ? [NSString stringWithUTF8String:optarg] : @"";
        switch (opt) {
            case 'V':
                verbose = TRUE;
                break;
            case 'D':
                dump = TRUE;
                break;
            case 'd':
                debug = TRUE;
                break;
            case 'i':
                input = val ? [NSURL fileURLWithPath:val] : nil;
                break;
            case 'o':
                output = val ? [NSURL fileURLWithPath:val] : nil;
                break;
            case 'v':
                ve = val;
                break;
            case 'a':
                ae = val;
                break;
            case 'c':
                co = val;
                break;
            case -128:
                meve = val;
                break;
            case -129:
                mevf = val;
                break;
            case -264:
                mex264 = val;
                break;
            case -265:
                mex265 = val;
                break;
            default:
                NSLog(@"ERROR: unknown parameter = \"%s\"", argv[optind]);
                goto error;
                break;
        }
    }
    
    // Quick Options Check
    if (!(input && output)) {
        NSLog(@"ERROR: Either input or output is not available.");
        goto error;
    }
    if (ve != NULL) {
        if (meve || mex264 || mex265) {
            NSLog(@"ERROR: -ve is not compatible with -meve/-mex264/-mex265.");
            goto error;
        }
    }
    if (mex264 && mex265) {
        NSLog(@"ERROR: Either -mex264 or -mex265 should be used.");
        goto error;
    }
    
    // Instanciate METranscoder
    transcoder = [METranscoder transcoderWithInput:input output:output];
    if (!transcoder) {
        NSLog(@"ERROR: Invalid input or output.");
        goto error;
    }
    
    // Configure METranscoder with meve/mevf/mex264/mex265 or ve/ae/co
    {
        NSArray *vList = [transcoder.inMovie tracksWithMediaType:AVMediaTypeVideo];
        NSArray *mList = [transcoder.inMovie tracksWithMediaType:AVMediaTypeMuxed];
        videoTracks = [vList arrayByAddingObjectsFromArray:mList];
        audioTracks = [transcoder.inMovie tracksWithMediaType:AVMediaTypeAudio];
    }
    if (meve || mevf) {
        if (videoTracks.count == 0) {
            NSLog(@"ERROR: No video track is available.");
            goto error;
        }
        // setup MEManager for each video tracks
        for (AVAssetTrack* track in videoTracks) {
            CMPersistentTrackID trackID = track.trackID;
            MEManager* manager = [MEManager new];
            if (meve) {
                if (parseOptMEVE(meve, manager) == FALSE) {
                    NSLog(@"ERROR: Video parameter meve is invalid.");
                    goto error;
                }
                if (mex264) {
                    manager.videoEncoderSetting[kMEVEx264_paramsKey] = mex264;
                }
                if (mex265) {
                    manager.videoEncoderSetting[kMEVEx264_paramsKey] = mex265;
                }
            }
            if (mevf) {
                manager.videoFilterString = mevf;
            }
            manager.initialDelayInSec = initialDelayInSec;
            manager.verbose = verbose;
            [transcoder registerMEManager:manager for:trackID];
            if (debug) {
                manager.log_level = 48; //AV_LOG_DEBUG
            }
        }
    }
    if (ve) {
        if (videoTracks.count == 0) {
            NSLog(@"ERROR: No video track is available.");
            goto error;
        }
        if (parseOptVE(ve, transcoder) == FALSE) {
            NSLog(@"ERROR: Video parameter ve is invalid.");
            goto error;
        }
    }
    if (ae) {
        if (audioTracks.count == 0) {
            NSLog(@"ERROR: No audio track is available.");
            goto error;
        }
        if (parseOptAE(ae, transcoder) == FALSE) {
            NSLog(@"ERROR: Audio parameter ae is invalid.");
            goto error;
        }
        
        // Register MEAudioConverter if channel layout or volume is specified
        if (transcoder.param[kAudioChannelLayoutTagKey] || transcoder.param[kAudioVolumeKey]) {
            for (AVAssetTrack* track in audioTracks) {
                CMPersistentTrackID trackID = track.trackID;
                MEAudioConverter* audioConverter = [MEAudioConverter new];
                
                // Configure volume if specified
                if (transcoder.param[kAudioVolumeKey]) {
                    NSNumber* volumeNum = transcoder.param[kAudioVolumeKey];
                    audioConverter.volumeDb = volumeNum.doubleValue;
                    if (verbose) {
                        NSLog(@"Setting audio volume to %.1f dB for track %d", audioConverter.volumeDb, trackID);
                    }
                }
                
                [transcoder registerMEAudioConverter:audioConverter for:trackID];
            }
        }
    }
    if (co) {
        transcoder.param[kCopyOtherMediaKey] = @YES;
    }
    if (verbose) {
        transcoder.verbose = TRUE;
    }
    if (dump) {
        transcoder.progressCallback = ^(NSDictionary* info) {
            NSString* type = (NSString*)info[kProgressMediaTypeKey];
            if ( [@"vide" compare:type] == NSOrderedSame ) {
                NSString* tag = (NSString*)info[kProgressTagKey];
                NSNumber* count = (NSNumber*)info[kProgressCountKey];
                NSNumber* percent = (NSNumber*)info[kProgressPercentKey];
                NSNumber* dtsNum = (NSNumber*)info[kProgressDTSKey];
                NSNumber* ptsNum = (NSNumber*)info[kProgressPTSKey];
                NSNumber* trackID = (NSNumber*)info[kProgressTrackIDKey];
                float progress = MIN(percent.floatValue, 99.99);
                NSLog(@"%2d|%@|%@|%5.2f%%|dts:%7.2f|pts:%7.2f|cnt:%6d|",
                      trackID.intValue, type, tag, progress,
                      dtsNum.floatValue, ptsNum.floatValue, count.intValue);
            }
        };
        transcoder.callbackQueue = dispatch_get_main_queue();
    } else {
        __weak typeof(transcoder) wx = transcoder;
        transcoder.progressCallback = ^(NSDictionary* info) {
            NSString* type = (NSString*)info[kProgressMediaTypeKey];
            if ( [@"vide" compare:type] == NSOrderedSame ) {
                int lastProgress = wx.lastProgress;
                int newProgress = 0;
                NSNumber* percent = (NSNumber*)info[kProgressPercentKey];
                if (percent != nil) {
                    newProgress = [percent floatValue] * 2;
                    if (lastProgress < newProgress) {
                        wx.lastProgress = newProgress;
                        NSLog(@"UpdatePercentPhase:(%5.1f%%)", [percent floatValue]);
                    }
                }
            }
        };
        transcoder.callbackQueue = dispatch_get_main_queue();
    }
    
    return transcoder;
    
error:
    return nil;
}

/* =================================================================================== */
// MARK: -
/* =================================================================================== */

int main(int argc, char * const *argv) {
    @autoreleasepool {
        // validate opt and prepare transcoder object
        METranscoder* transcoder = validateOpt(argc, argv);
        if (!transcoder) {
            exit(EXIT_FAILURE);
        }
        
        // Start transcoder
        [transcoder startAsync];
        
        // Setup signal handler
        monitor_block_t monitorHandler = ^{
            NSError* err = transcoder.finalError;
            BOOL success = transcoder.finalSuccess;
            BOOL cancel = transcoder.cancelled;
            if (success) {
                //NSLog(@"Transcode completed.");
                finishMonitor(EXIT_SUCCESS);
            }
            if (cancel) {
                //NSLog(@"Transcode canceled.");
                while (transcoder.writerIsBusy) {
                    usleep(USEC_PER_SEC / 20);
                }
                finishMonitor(128 + lastSignal()); // 128 + SIGNUMBER
            }
            if (err) {
                NSLog(@"Transcode failed(%@).", err);
                finishMonitor(EXIT_FAILURE);
            }
        };
        cancel_block_t cancelHandler = ^{
            [transcoder cancelAsync];
        };
        startMonitor(monitorHandler, cancelHandler); // it never returns
    }
    return 0;
}

NS_ASSUME_NONNULL_END
