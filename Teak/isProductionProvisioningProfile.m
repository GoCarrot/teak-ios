/*
 Copyright 2009-2016 Urban Airship Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#import <Foundation/Foundation.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"

#define UA_LTRACE
#define UA_LERR
#define UA_LDEBUG

BOOL isProductionProvisioningProfile(NSString* profilePath) {

   // Attempt to read this file as ASCII (rather than UTF-8) due to the binary blocks before and after the plist data
   NSError *err = nil;
   NSString *embeddedProfile = [NSString stringWithContentsOfFile:profilePath
                                                         encoding:NSASCIIStringEncoding
                                                            error:&err];
   UA_LTRACE((void)(@"Profile path: %@"), profilePath);

   if (err) {
      UA_LERR(@"No mobile provision profile found or the profile could not be read. Defaulting to production mode.");
      return YES;
   }

   NSDictionary *plistDict = nil;
   NSScanner *scanner = [[NSScanner alloc] initWithString:embeddedProfile];

   if ([scanner scanUpToString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" intoString:nil]) {
      NSString *plistString = nil;
      if ([scanner scanUpToString:@"</plist>" intoString:&plistString]) {
         NSData *data = [[plistString stringByAppendingString:@"</plist>"] dataUsingEncoding:NSUTF8StringEncoding];
         plistDict = [NSPropertyListSerialization propertyListWithData:data
                                                               options:NSPropertyListImmutable
                                                                format:nil
                                                                 error:nil];
      }
   }

   // Tell the logs a little about the app
   if ([plistDict valueForKeyPath:@"ProvisionedDevices"]){
      if ([[plistDict valueForKeyPath:@"Entitlements.get-task-allow"] boolValue]) {
         UA_LDEBUG(@"Debug provisioning profile. Uses the APNS Sandbox Servers.");
      } else {
         UA_LDEBUG(@"Ad-Hoc provisioning profile. Uses the APNS Production Servers.");
      }
   } else if ([[plistDict valueForKeyPath:@"ProvisionsAllDevices"] boolValue]) {
      UA_LDEBUG(@"Enterprise provisioning profile. Uses the APNS Production Servers.");
   } else {
      UA_LDEBUG(@"App Store provisioning profile. Uses the APNS Production Servers.");
   }

   NSString *apsEnvironment = [plistDict valueForKeyPath:@"Entitlements.aps-environment"];
   UA_LDEBUG((void)(@"APS Environment set to %@"), apsEnvironment);
   if ([@"development" isEqualToString:apsEnvironment]) {
      return NO;
   }

   // Let the dev know if there's not an APS entitlement in the profile. Something is terribly wrong.
   if (!apsEnvironment) {
      UA_LERR(@"aps-environment value is not set. If this is not a simulator, ensure that the app is properly provisioned for push");
   }

   return YES;// For safety, assume production unless the profile is explicitly set to development
}

#pragma clang diagnostic pop
