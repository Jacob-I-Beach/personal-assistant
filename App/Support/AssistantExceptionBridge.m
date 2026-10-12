#import "AssistantExceptionBridge.h"

@implementation AssistantExceptionBridge
+ (BOOL)perform:(void (NS_NOESCAPE ^)(void))operation error:(NSError **)error {
    @try {
        operation();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"Assistant.FrameworkValidation" code:1 userInfo:@{
                NSLocalizedDescriptionKey: [@"Health could not accept this request. " stringByAppendingString: exception.reason ?: @"The selected types are unavailable in this installation."],
                NSLocalizedFailureReasonErrorKey: exception.reason ?: exception.name
            }];
        }
        return NO;
    }
}
@end
