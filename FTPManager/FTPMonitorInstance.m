#import "FTPMonitorInstance.h"
#import "FTPManager.h"
#import "ZipArchive.h"
#define FTP_ACCOUNT @"hmc"
#define FTP_PASSWORD @"123456"

@interface FTPMonitorInstance()

@property (nonatomic, strong) FMServer* server;
@property (nonatomic, strong) FTPManager* manager;

@end

@implementation FTPMonitorInstance


+ (instancetype)shareInstance {
    static FTPMonitorInstance *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FTPMonitorInstance alloc] init];
    });
    
    return instance;
}

- (void)configFTPMonitorWithUserModel:(UserModel *)userModel {
    self.manager = [[FTPManager alloc] init];
    NSString *host = @"192.168.1.1";
    FMServer *server =  [FMServer serverWithDestination:host username:FTP_ACCOUNT password:FTP_PASSWORD];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 创建ftp client目录
        NSString *folder = [NSString stringWithFormat:@"%d",[DataModelInstance shareInstance].userModel.client_id.intValue];
        BOOL isSuccess = [self.manager createNewFolder:folder atServer:server];
        DDLogInfo(@"---创建ftp client目录 %@---",isSuccess ? @"成功":@"失败");
        
        // 创建ftp clientUser目录
        folder = [NSString stringWithFormat:@"%@/%d",folder,
                  [DataModelInstance shareInstance].userModel.client_user_id.intValue];
        isSuccess = [self.manager createNewFolder:folder atServer:server];
        DDLogInfo(@"---创建ftp clientUser目录 %@---",isSuccess ? @"成功":@"失败");
        
        // 创建ftp 门头照根目录
        NSString *storeDoorfolder = @"bn";
        isSuccess = [self.manager createNewFolder:storeDoorfolder atServer:server];
        DDLogInfo(@"---创建ftp 门头照根目录 %@---",isSuccess ? @"成功":@"失败");
        
        // 创建ftp 门头照client目录
        storeDoorfolder = [NSString stringWithFormat:@"%@/%d",storeDoorfolder,
                           [DataModelInstance shareInstance].userModel.client_id.intValue];
        isSuccess = [self.manager createNewFolder:storeDoorfolder atServer:server];
        DDLogInfo(@"---创建ftp 门头照client目录 %@---",isSuccess ? @"成功":@"失败");
    });
    
    // 全局变量设定
    NSString *url = [NSString stringWithFormat:@"%@:%@/%d/%d", host, FTP_PORT,
                     [DataModelInstance shareInstance].userModel.client_id.intValue,
                     [DataModelInstance shareInstance].userModel.client_user_id.intValue
                     ];
    self.server = [FMServer serverWithDestination:url username:FTP_ACCOUNT password:FTP_PASSWORD];
}

- (void)createFolder:(NSString *)folderName {
    BOOL succeeded =  [self.manager createNewFolder:folderName atServer:self.server];
    
    DDLogWarn(@"---创建ftp目录 %@:%@---", folderName, succeeded ? @"成功":@"失败");
}

- (BOOL)uploadFile:(NSString *)filePath {
    // 过滤空图片
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        NSNumber *fileSizeNumber = [fileAttributes objectForKey:NSFileSize];
        long long fileSize = [fileSizeNumber longLongValue];
        if (fileSize == 0) {
            DDLogWarn(@"file(%@) fileSize is 0! ", filePath);
            NSError *error;
            BOOL succeeded = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
            DDLogError(@"删除空图片 %@:%@", filePath, succeeded ? @"成功":@"失败");
            return NO;
        }
    }else{
        DDLogError(@"filePath(%@) is no exist ", filePath);
        return NO;
    }
    
    NSString *host = @"192.168.1.1";
    FMServer *server = nil;
    // 上传门头照
    if([filePath rangeOfString:@"BN_I_"].location != NSNotFound){
        NSString *url = [NSString stringWithFormat:@"%@:%@/bn/%d", host, FTP_PORT,
                         [DataModelInstance shareInstance].userModel.client_id.intValue];
        server = [FMServer serverWithDestination:url username:FTP_ACCOUNT password:FTP_PASSWORD];
    }else{
        NSString *url = [NSString stringWithFormat:@"%@:%@/%d/%d", host, FTP_PORT,
                         [DataModelInstance shareInstance].userModel.client_id.intValue,
                         [DataModelInstance shareInstance].userModel.client_user_id.intValue
                         ];
        server = [FMServer serverWithDestination:url username:FTP_ACCOUNT password:FTP_PASSWORD];
    }
    DDLogInfo(@"正在上传文件（%@）",filePath);
    BOOL success = [self.manager uploadFile:[NSURL URLWithString:filePath] toServer:server];
    DDLogInfo(@"文件（%@）上传已完成，上传%@",filePath,success?@"成功":@"失败");
    return success;
}


- (void)uploadFolderFile:(NSString *)folderName {
    NSFileManager* fm=[NSFileManager defaultManager];
    
    NSArray *files = [fm subpathsAtPath: folderName];
    
    BOOL isAllNotify = NO;
    BOOL isNomalNotify = NO;
    for (NSString *fileName in files) {
        NSString *filePath = [NSString stringWithFormat:@"%@/%@", folderName, fileName];
        if (![fileName hasSuffix:@".mobi"] && ![fileName hasSuffix:@".bak"] && ![fileName hasSuffix:@".DS_Store"]) {
            if([self uploadFile:filePath]) {
                if([fileName rangeOfString:@"BN_I_"].location != NSNotFound){
                    isAllNotify = YES;
                }else{
                    isNomalNotify = YES;
                }
                NSError *error;
                BOOL succeeded = [fm removeItemAtPath:filePath error:&error];
                DDLogError(@"删除文件 %@:%@", filePath, succeeded ? @"成功":@"失败");
            }
        }
    }
    
    if (isAllNotify || isNomalNotify) {
        /*
         每上传成功开线程60s后调用通知接口，若60s没有其他图片上传(时间比较得知) 则执行，否则放弃
         */
        if(isAllNotify){
            [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kUserDefaults_allImageNotifyDate];
            // 若普通照片 也要通知 将其记录时间改成当前时间 ,不通知
            NSDate *normalDate = (NSDate*)[[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaults_normalImageNotifyDate];
            if (([NSDate secondsAwayFrom:[NSDate date] dateSecond:normalDate] <= 60) && normalDate) {
                [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kUserDefaults_normalImageNotifyDate];
            }else{
                if (normalDate) {
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserDefaults_normalImageNotifyDate];
                }
            }
        }else{
            [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kUserDefaults_normalImageNotifyDate];
            // 若门店照片 也要通知 将其记录时间改成当前时间 ,不通知,下次通知
            NSDate *doorDate = (NSDate*)[[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaults_allImageNotifyDate];
            if (([NSDate secondsAwayFrom:[NSDate date] dateSecond:doorDate] <= 60) && doorDate) {
                [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kUserDefaults_allImageNotifyDate];
            }else{
                if (doorDate) {
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUserDefaults_allImageNotifyDate];
                }
            }
        }
        [self performSelector:@selector(uploadImageNotify) withObject:nil afterDelay:60];
    }
}

// 图片FTP上传服务器实时压缩通知接口
- (void)uploadImageNotify {
    
    //  type  类型，1：普通通知  2：门店照片压缩同步(bn开头的照片和普通照片)
    NSString *type = nil;
    NSDate *doorDate = (NSDate*)[[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaults_allImageNotifyDate];
    NSDate *normalDate = (NSDate*)[[NSUserDefaults standardUserDefaults] objectForKey:kUserDefaults_normalImageNotifyDate];
    
    DDLogDebug(@"doorDate:%@,normalDate:%@,nowDate:%@",doorDate,normalDate,[NSDate date]);
    if (([NSDate secondsAwayFrom:[NSDate date] dateSecond:doorDate] >= 60) && doorDate) {
        type = @"2";
    }else if (([NSDate secondsAwayFrom:[NSDate date] dateSecond:normalDate] >= 60) && normalDate) {
        type = @"1";
    }
    if (type != nil) {
        NSMutableDictionary *requestDict = [[NSMutableDictionary alloc] init];
        [requestDict setValue:[DataModelInstance shareInstance].userModel.client_id forKey:@"clientId"];
        [requestDict setValue:[DataModelInstance shareInstance].userModel.client_user_id forKey:@"clientUserId"];
        [requestDict setValue:type forKey:@"type"];
        
        [[[UIViewController alloc] init] requstAPI:API_NAME_IMAGE_NOTIFY paramDict:requestDict hud:nil success:^(AFHTTPRequestOperation *operation, id responseObject, MBProgressHUD *hud) {
            DDLogInfo(@"%@照片上传服务器通知成功！",[type isEqualToString:@"2"]?@"门店":@"普通");
        } failure:^(AFHTTPRequestOperation *operation, NSError *error, MBProgressHUD *hud) {
            DDLogInfo(@"%@照片上传服务器通知失败！error:%@",[type isEqualToString:@"2"]?@"门店":@"普通",error);
        }];
    }
}

- (void)uploadLogFile:(NSMutableArray *)commandArray {
    //yyyy-MM-dd hh:mm:ss_<client_user_id>_
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *folderName = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingString:@"/User"];
    NSArray *tempFiles = [fm subpathsAtPath: folderName];
    for (NSString *subFolder in tempFiles) {
        if([subFolder hasSuffix:@".zip"]){
            [fm removeItemAtPath:[NSString stringWithFormat:@"%@/%@", folderName, subFolder] error:nil];
        }
    }
    for(NSDictionary *dict in commandArray){
        NSMutableDictionary *requestDic = [[NSMutableDictionary alloc] init];
        [requestDic setValue:[DataModelInstance shareInstance].userModel.client_id forKey:@"clientId"];
        [requestDic setValue:[DataModelInstance shareInstance].userModel.client_user_id forKey:@"clientUserId"];
        [requestDic setValue:[dict objectForKey:@"cmdId"] forKey:@"commandId"];
        
        ZipArchive *zip = [[ZipArchive alloc] init];
        NSString *currentFilePath = @"";
        NSString *zipName = [[NSDate currentTimeString:kTimeFormatNOSpace] stringByAppendingString:[NSString stringWithFormat:@"_%@_", [DataModelInstance shareInstance].userModel.client_user_id]];
        BOOL hasFile = NO;
        NSString *lowerCMD = [[dict objectForKey:@"cmd"] lowercaseString];
        
        if([lowerCMD hasPrefix:@"check_data"]){
            continue;
        }else if([lowerCMD isEqualToString:@"alldb"]){
            //上传该设备所有db
            zipName = [zipName stringByAppendingString:@"all_db.zip"];
            currentFilePath = [folderName stringByAppendingString:[NSString stringWithFormat:@"/%@",zipName]];
            [zip CreateZipFile2:currentFilePath];
            NSArray *files = [fm subpathsAtPath: folderName];
            for (NSString *subFolder in files) {
                if([subFolder hasSuffix:@"/ChannelPlus.db"]){
                    NSString *filePath = [NSString stringWithFormat:@"%@/%@", folderName, subFolder];
                    if([fm fileExistsAtPath:filePath]){
                        NSString *newName = [NSString stringWithFormat:@"%@.db",subFolder];
                        [zip addFileToZip:filePath newname:newName];
                        hasFile = YES;
                    }
                }
            }
        }else if([lowerCMD isEqualToString:@"db"]){
            //上传当前登录用户的db
            zipName = [zipName stringByAppendingString:@"db.zip"];
            currentFilePath = [folderName stringByAppendingString:[NSString stringWithFormat:@"/%@",zipName]];
            [zip CreateZipFile2:currentFilePath];
            NSString *filePath = [NSString stringWithFormat:@"%@/%@_%@/ChannelPlus.db", folderName, [DataModelInstance shareInstance].userModel.client_id, [DataModelInstance shareInstance].userModel.client_user_id];
            if([fm fileExistsAtPath:filePath]){
                [zip addFileToZip:filePath newname:@"ChannelPlus.db"];
                hasFile = YES;
            }
        }else if([lowerCMD hasPrefix:@"logs-"]){
            //logs-<d> :上传d天以内的log  ( logs-5 )
            zipName = [zipName stringByAppendingString:@"log.zip"];
            currentFilePath = [folderName stringByAppendingString:[NSString stringWithFormat:@"/%@",zipName]];
            [zip CreateZipFile2:currentFilePath];
            NSArray *tempArray = [NSDate getAllDatesByCurrentDate:[NSDate date] days:[[lowerCMD substringFromIndex:5] intValue]];
            for(NSDate *date in tempArray){
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"YYYY_MM_dd"];
                NSString *tempName = [formatter stringFromDate:date];
                NSArray *files = [fm subpathsAtPath:[NSString stringWithFormat:@"%@/Log", folderName]];
                for(NSString *fileName in files){
                    if([fileName hasPrefix:tempName]){
                        [zip addFileToZip:[NSString stringWithFormat:@"%@/Log/%@", folderName, fileName] newname:fileName];
                        hasFile = YES;
                    }
                }
            };
        }else if([lowerCMD hasPrefix:@"log-"]){
            //log-<yyyy-MM-dd> : 上传指定日期的日志  （log-2015-02-13）
            zipName = [zipName stringByAppendingString:@"log.zip"];
            currentFilePath = [folderName stringByAppendingString:[NSString stringWithFormat:@"/%@",zipName]];
            [zip CreateZipFile2:currentFilePath];
            NSString *tempName = [[lowerCMD substringFromIndex:4] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
            NSArray *files = [fm subpathsAtPath:[NSString stringWithFormat:@"%@/Log", folderName]];
            for(NSString *fileName in files){
                if([fileName hasPrefix:tempName]){
                    [zip addFileToZip:[NSString stringWithFormat:@"%@/Log/%@", folderName, fileName] newname:fileName];
                    hasFile = YES;
                }
            }
        }else if([lowerCMD isEqualToString:@"log"]){
            //log ：上传当天日志
            zipName = [zipName stringByAppendingString:@"log.zip"];
            currentFilePath = [folderName stringByAppendingString:[NSString stringWithFormat:@"/%@",zipName]];
            [zip CreateZipFile2:currentFilePath];
            NSString *tempName = [[NSDate currentTimeString:kShortTimeFormat] stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
            NSArray *files = [fm subpathsAtPath:[NSString stringWithFormat:@"%@/Log", folderName]];
            for(NSString *fileName in files){
                if([fileName hasPrefix:tempName]){
                    [zip addFileToZip:[NSString stringWithFormat:@"%@/Log/%@", folderName, fileName] newname:fileName];
                    hasFile = YES;
                }
            }
        }else if([lowerCMD hasPrefix:@"sync_data-"]){
            //sync_data-<name> : 上传临时数据文件
            zipName = [zipName stringByAppendingString:@"sync_data.zip"];
            currentFilePath = [folderName stringByAppendingString:[NSString stringWithFormat:@"/%@",zipName]];
            [zip CreateZipFile2:currentFilePath];
            NSString *fileName = [NSString stringWithFormat:@"%@", [lowerCMD substringFromIndex:10]];
            NSString *filePath = [NSString stringWithFormat:@"%@/%@_%@/sync_data/%@", folderName, [DataModelInstance shareInstance].userModel.client_id, [DataModelInstance shareInstance].userModel.client_user_id, fileName];
            if([fm fileExistsAtPath:filePath]){
                [zip addFileToZip:filePath newname:fileName];
                hasFile = YES;
            }
        }else if([lowerCMD isEqualToString:@"db_backup"]){
            zipName = [zipName stringByAppendingString:@"db_backup.zip"];
            currentFilePath = [folderName stringByAppendingString:[NSString stringWithFormat:@"/%@",zipName]];
            [zip CreateZipFile2:currentFilePath];
            NSArray *files = [fm subpathsAtPath:[NSString stringWithFormat:@"%@/%@_%@/db_backup", folderName, [DataModelInstance shareInstance].userModel.client_id, [DataModelInstance shareInstance].userModel.client_user_id]];
            for(NSString *fileName in files){
                [zip addFileToZip:[NSString stringWithFormat:@"%@/%@_%@/db_backup/%@", folderName, [DataModelInstance shareInstance].userModel.client_id, [DataModelInstance shareInstance].userModel.client_user_id, fileName] newname:fileName];
                hasFile = YES;
            }
        }
        
        [zip CloseZipFile2];
        if(hasFile == YES){
            for(int i = 0; i < 3; i++){
                if([self uploadFile:currentFilePath]){
                    [requestDic setValue:@"完成" forKey:@"exeResult"];
                    break;
                }else{
                    [requestDic setValue:@"失败" forKey:@"exeResult"];
                }
            }
        }else{
            [requestDic setValue:@"该文件没有找到" forKey:@"exeResult"];
        }
        [[NSFileManager defaultManager] removeItemAtPath:currentFilePath error:nil];
        
        [[[UIViewController alloc] init] requstAPI:API_NAME_COMMAND_EXE paramDict:requestDic hud:nil success:^(AFHTTPRequestOperation *operation, id responseObject, MBProgressHUD *hud) {
            
        } failure:^(AFHTTPRequestOperation *operation, NSError *error, MBProgressHUD *hud) {
            
        }];
    }
}

@end
