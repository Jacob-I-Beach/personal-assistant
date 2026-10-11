#import "AssistantExceptionBridge.h"

@implementation AssistantExceptionBridge
+ (BOOL)perform:(void (NS_NOESCAPE ^)(void))operation error:(NSError **)error {
    @try {
        operation();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"Assistant.FrameworkValidation" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"The system could not accept this access request. Your selection is kept so you can adjust it and try again.",
                NSLocalizedFailureReasonErrorKey: exception.reason ?: exception.name
            }];
        }
        return NO;
    }
}
@end
