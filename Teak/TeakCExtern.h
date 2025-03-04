#ifndef TeakCExtern_h_
#define TeakCExtern_h_

#import <objc/runtime.h>
#import <Foundation/Foundation.h>

extern BOOL TeakRequestPushAuthorization(BOOL includeProvisional);
extern void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret);

#endif
