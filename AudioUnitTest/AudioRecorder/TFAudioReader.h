//
//  TFAudioReader.h
//  VideoGather
//
//  Created by shiwei on 17/11/2.
//  Copyright © 2017年 shiwei. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TFAudioBufferData.h"
#import "TFStatusChecker.h"

//使用者主动读取音频数据，和output一样提供数据，但是output是主动推送数据
@protocol TFAudioReader <NSObject>

-(OSStatus)readFrames:(UInt32)framesNum toBufferData:(TFAudioBufferData *)bufferData;

@optional
//以packet为度量单位，对于编码压缩的类型实现/使用这个方法更好
-(OSStatus)readPackets:(UInt32)packetsNum toBufferData:(TFAudioBufferData *)bufferData;

@end
