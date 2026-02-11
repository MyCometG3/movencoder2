//
//  MEAudioConverter+Internal.h
//  movencoder2
//
//  Created by Takashi Mochizuki on 2018/11/03.
//
//  Copyright (C) 2018-2026 MyCometG3
//  SPDX-License-Identifier: GPL-2.0-or-later
//

#ifndef MEAudioConverter_Internal_h
#define MEAudioConverter_Internal_h

#import "MEAudioConverter.h"

NS_ASSUME_NONNULL_BEGIN

@interface MEAudioConverter ()
@property (strong, nonatomic) NSMutableData *audioBufferListPool;
@end

NS_ASSUME_NONNULL_END

#endif /* MEAudioConverter_Internal_h */
