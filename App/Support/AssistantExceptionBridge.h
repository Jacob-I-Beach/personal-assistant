#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Framework argument validation can raise Objective-C exceptions, which Swift
/// do/catch cannot handle. Use only at explicit synchronous framework boundaries.
@interface AssistantExceptionBridge : NSObject
+ (BOOL)perform:(void (NS_NOESCAPE ^)(void))operation error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
