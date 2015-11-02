#import <Foundation/Foundation.h>

@interface FTPMonitorInstance : NSObject

+ (instancetype)shareInstance;

- (void)configFTPMonitorWithUserModel:(UserModel *)userModel;
- (void)createFolder:(NSString *)folderName;
- (BOOL)uploadFile:(NSString *)filePath;
- (void)uploadFolderFile:(NSString *)folderName;
- (void)uploadLogFile:(NSMutableArray *)commandArray;

@end
