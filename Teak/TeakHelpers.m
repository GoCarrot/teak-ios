/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <Foundation/Foundation.h>

NSString* TeakNSStringOrNilFor(id object) {
  if (object == nil) return nil;

  NSString* ret = nil;
  @try {
    ret = ((object == nil || [object isKindOfClass:[NSString class]]) ? object : [object stringValue]);
  } @catch (NSException* ignored) {
    ret = nil;
  }
  return ret;
}

NSString* TeakURLEscapedString(NSString* inString) {
  static NSCharacterSet* rfc3986Reserved = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    rfc3986Reserved = [[NSCharacterSet characterSetWithCharactersInString:@"!*'();:@&=+$,/?#[]"] invertedSet];
  });

  if (inString == nil) return nil;
  return [inString stringByAddingPercentEncodingWithAllowedCharacters:rfc3986Reserved];
}

BOOL TeakBoolFor(id object) {
  if (object == nil || object == [NSNull null]) {
    return NO;
  }

  return [object boolValue];
}

///// Recursive form encode

NSString* TeakFormEncode(NSString* name, id value, BOOL escape) {
  NSMutableArray* listOfThingsToJoin = [[NSMutableArray alloc] init];
  if ([value isKindOfClass:NSDictionary.class]) {
    NSError* error = nil;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
    if (error) {
      [listOfThingsToJoin addObject:[NSString stringWithFormat:@"%@=%@", name, [value description]]];
    } else {
      NSString* valueString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
      [listOfThingsToJoin addObject:[NSString stringWithFormat:@"%@=%@", name, valueString]];
    }
    // TODO: Change to this once server supports this encoding format for signing strings
    //    for (id key in value) {
    //      [listOfThingsToJoin addObject:TeakFormEncode([NSString stringWithFormat:@"%@[%@]", name, key], value[key], escape)];
    //    }
  } else if ([value isKindOfClass:NSArray.class]) {
    for (id v in value) {
      [listOfThingsToJoin addObject:TeakFormEncode([NSString stringWithFormat:@"%@[]", name], v, escape)];
    }
  } else {
    if (name == nil) {
      [listOfThingsToJoin addObject:escape ? TeakURLEscapedString(TeakNSStringOrNilFor(value)) : TeakNSStringOrNilFor(value)];
    } else {
      [listOfThingsToJoin addObject:[NSString stringWithFormat:@"%@=%@", name, escape ? TeakURLEscapedString(TeakNSStringOrNilFor(value)) : TeakNSStringOrNilFor(value)]];
    }
  }
  return [listOfThingsToJoin componentsJoinedByString:@"&"];
}

///// Assign NSDictionary into 'application/x-www-form-urlencoded' request

void TeakAssignPayloadToRequest(NSMutableURLRequest* request, NSDictionary* payload) {
  NSMutableData* postData = [[NSMutableData alloc] init];
  NSMutableArray* escapedPayloadComponents = [[NSMutableArray alloc] init];
  for (NSString* key in payload) {
    id value = payload[key];
    [escapedPayloadComponents addObject:TeakFormEncode(key, value, YES)];
  }
  NSString* escapedPayloadString = [escapedPayloadComponents componentsJoinedByString:@"&"];
  [postData appendData:[escapedPayloadString dataUsingEncoding:NSUTF8StringEncoding]];

  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:postData];
  [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
}
