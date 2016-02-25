/*
 * Copyright 2010-2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * A copy of the License is located at
 *
 *  http://aws.amazon.com/apache2.0
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

#import <Foundation/Foundation.h>

// NOTE: Not using categories as static libs require additional linker flags
// http://stackoverflow.com/questions/2567498/objective-c-categories-in-static-library
@interface NSDataWithBase64 : NSObject

/**
 * Return a base64 encoded representation of the data.
 *
 * @return base64 encoded representation of the data.
 */
+(NSString *) base64EncodedStringFromData:(NSData*)data;

/**
 * Decode a base-64 encoded string into a new NSData object.
 *
 * @return NSData with the data represented by the encoded string.
 */
+(NSData *) dataWithBase64EncodedString:(NSString *)encodedString;
@end