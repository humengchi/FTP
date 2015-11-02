//
//  FTPMonitor.h
//  ChannelPlus
//
//  Created by Peter on 15/2/3.
//  Copyright (c) 2015年 Peter. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FTPMonitorInstance : NSObject

+ (instancetype)shareInstance;

- (void)configFTPMonitorWithUserModel:(UserModel *)userModel;
- (void)createFolder:(NSString *)folderName;
- (BOOL)uploadFile:(NSString *)filePath;
- (void)uploadFolderFile:(NSString *)folderName;
- (void)uploadLogFile:(NSMutableArray *)commandArray;

@end
