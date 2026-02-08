//
//  parseUtil.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2019/06/16.
//
//  Copyright (C) 2019-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

/**
 * @header parseUtil.h
 * @abstract Internal API - Parameter parsing utilities
 * @discussion
 * This header is part of the internal implementation of movencoder2.
 * It is not intended for public use and its interface may change without notice.
 *
 * @internal This is an internal API. Do not use directly.
 */

#ifndef parseUtil_h
#define parseUtil_h

@import Foundation;
@import AVFoundation;

NS_ASSUME_NONNULL_BEGIN

/* =================================================================================== */
// MARK: - parse utilities
/* =================================================================================== */

extern NSString* const separator;
extern NSString* const equal;
extern NSString* const optSeparator;

NSNumber* _Nullable parseInteger(NSString* val);
NSNumber* _Nullable parseDouble(NSString* val);
NSValue* _Nullable parseSize(NSString* val);
NSValue* _Nullable parseRect(NSString* val);
NSValue* _Nullable parseTime(NSString* val);
NSNumber* _Nullable parseBool(NSString* val);
NSDictionary* _Nullable parseCodecOptions(NSString* val);
NSNumber* _Nullable parseLayoutTag(NSString* val); // Supports AAC layout names and integer values

NS_ASSUME_NONNULL_END

#endif /* parseUtil_h */
