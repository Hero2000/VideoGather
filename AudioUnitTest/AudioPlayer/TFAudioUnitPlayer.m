//
//  TFAudioUnitPlayer.m
//  VideoGather
//
//  Created by shiwei on 17/10/25.
//  Copyright © 2017年 shiwei. All rights reserved.
//

#import "TFAudioUnitPlayer.h"
#import <AVFoundation/AVFoundation.h>

static UInt32 renderAudioElement = 0;   //输出给硬件的组件编号
static UInt32 recordAudioElement = 1;   //接收硬件数据的组件编号

@interface TFAudioUnitPlayer (){
    ExtAudioFileRef audioFile;
    AudioStreamBasicDescription fileDesc;
    UInt32 packetSize; // pacm is uncompressed/unencoded, so 1 packet = 1 frame. Packet size is also frame size.
    
    NSString *_filePath;
    
    AudioUnit audioUnit;
    
    AudioFileStreamID fileStreamID;
}

@end

@implementation TFAudioUnitPlayer

-(void)playLocalFile:(NSString *)filePath{
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:nil]) {
        NSLog(@"audio play: no file at: %@",filePath);
        return;
    }
    
    _filePath = filePath;
    
    //plan1: AAC,ExtAudioFile
    [self setupExtAudioFileReader];
    
    //plan2: AAC,AudioFileStream
//    [self setupAudioFileStream];
}

-(void)stop{
    
    if (audioFile) {
        ExtAudioFileDispose(audioFile);
    }
    
    if (audioUnit) {
        AudioOutputUnitStop(audioUnit);
        
        AudioComponentInstanceDispose(audioUnit);
    }
}

#pragma mark - Ext audio file

-(void)setupExtAudioFileReader{
    
    NSURL *fileURL = [NSURL fileURLWithPath:_filePath];
    OSStatus status = ExtAudioFileOpenURL((__bridge CFURLRef)fileURL, &audioFile);
    
    TFCheckStatusGoToFail(status, ([NSString stringWithFormat:@"open ExtAudioFile: %@",_filePath]))
    
    UInt32 size = sizeof(fileDesc);
    status = ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &size, &fileDesc);
    
    TFCheckStatusGoToFail(status, @"ExtAudioFile get file format")
    
    //read with pcm format
    AudioStreamBasicDescription clientDesc;
    clientDesc.mSampleRate = fileDesc.mSampleRate;
    clientDesc.mFormatID = kAudioFormatLinearPCM;
    clientDesc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    clientDesc.mReserved = 0;
    clientDesc.mChannelsPerFrame = 1; //2
    clientDesc.mBitsPerChannel = 16;
    clientDesc.mFramesPerPacket = 1;
    clientDesc.mBytesPerFrame = clientDesc.mChannelsPerFrame * clientDesc.mBitsPerChannel / 8;
    clientDesc.mBytesPerPacket = clientDesc.mBytesPerFrame;
    
    size = sizeof(clientDesc);
    status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, size, &clientDesc);
    
    size = sizeof(packetSize);
    ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_ClientMaxPacketSize, &size, &packetSize);
    NSLog(@"read pcm packet/frame size: %d",(unsigned int)packetSize);
    
    TFCheckStatusGoToFail(status, @"ExtAudioFile set client format")
    
    [self setupAudioUnitRenderWithAudioDesc:clientDesc];
    return;
    
fail:
    ExtAudioFileDispose(audioFile);
    audioFile = nil;
}

-(OSStatus)readFrames:(UInt32)framesNum toBufferList:(AudioBufferList *)bufferList{
    OSStatus status = ExtAudioFileRead(audioFile, &framesNum, bufferList);
    
    TFCheckStatusUnReturn(status, @"ExtAudioFile set client format")
    
    return status;
}

#pragma mark - audio file stream

-(void)setupAudioFileStream{
    
    AudioFileTypeID fileType = 0; // kAudioFileAAC_ADTSType
    AudioFileStreamOpen((__bridge void * _Nullable)(self), audioStreamPropertyListenCallback, audioStreamPacketCallback, fileType, &fileStreamID);
}

void audioStreamPropertyListenCallback(
                                             void *							inClientData,
                                             AudioFileStreamID				inAudioFileStream,
                                             AudioFileStreamPropertyID		inPropertyID,
                                       AudioFileStreamPropertyFlags *	ioFlags){
    
}

void audioStreamPacketCallback(
                               void *							inClientData,
                               UInt32							inNumberBytes,
                               UInt32							inNumberPackets,
                               const void *					inInputData,
                               AudioStreamPacketDescription	*inPacketDescriptions){
    
}

#pragma mark -

-(void)setupAudioUnitRenderWithAudioDesc:(AudioStreamBasicDescription)audioDesc{
    
    //componentDesc是筛选条件 component是组件的抽象，对应class的角色，componentInstance是具体的组件实体，对应object角色。
    AudioComponentDescription componentDesc;
    componentDesc.componentType = kAudioUnitType_Output;
    componentDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    componentDesc.componentFlags = 0;
    componentDesc.componentFlagsMask = 0;
    componentDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent component = AudioComponentFindNext(NULL, &componentDesc);
    OSStatus status = AudioComponentInstanceNew(component, &audioUnit);
    
    TFCheckStatusUnReturn(status, @"instance new audio component");
    
    //open render output
    UInt32 falg = 1;
    status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, renderAudioElement, &falg, sizeof(UInt32));
    
    TFCheckStatusUnReturn(status, @"enable IO");
    
    //set render input format
    status = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, renderAudioElement, &audioDesc, sizeof(audioDesc));
    
    TFCheckStatusUnReturn(status, @"set render input format");
    
    //set render callback to process audio buffers
    AURenderCallbackStruct callbackSt;
    callbackSt.inputProcRefCon = (__bridge void * _Nullable)(self);
    callbackSt.inputProc = playAudioBufferCallback;
    AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Group, renderAudioElement, &callbackSt, sizeof(callbackSt));
    
    NSError *error = nil;
    [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error) {
        NSLog(@"audio session set category: %@",error);
        return;
    }
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
        NSLog(@"active audio session: %@",error);
        return;
    }
    
    AudioOutputUnitStart(audioUnit);
    
    NSLog(@"audio play started!");
    
    if (status != 0) {
        AudioComponentInstanceDispose(audioUnit);
        audioUnit = nil;
    }
}


#pragma mark - callback

OSStatus playAudioBufferCallback(	void *							inRefCon,
                    AudioUnitRenderActionFlags *	ioActionFlags,
                    const AudioTimeStamp *			inTimeStamp,
                    UInt32							inBusNumber,
                    UInt32							inNumberFrames,
                                 AudioBufferList * __nullable	ioData){
    
    TFAudioUnitPlayer *player = (__bridge TFAudioUnitPlayer *)(inRefCon);
    
    UInt32 framesPerPacket = player->fileDesc.mFramesPerPacket;
    return [player readFrames:framesPerPacket toBufferList:ioData];
}

-(void)playPCMBuffer:(void *)buffer{
    
}

@end
