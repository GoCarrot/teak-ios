/* Teak -- Copyright (C) 2017 GoCarrot Inc.
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

#import <StoreKit/StoreKit.h>

typedef void (^ProductRequestCallback)(NSDictionary* _Nonnull, SKProductsResponse* _Nullable);

@interface SKPaymentObserver : NSObject
- (nonnull id)init;
@end

@interface ProductRequest : NSObject <SKProductsRequestDelegate>
+ (ProductRequest* _Nullable)productRequestForSku:(NSString* _Nonnull)sku callback:(ProductRequestCallback _Nonnull)callback;

- (void)productsRequest:(SKProductsRequest* _Nonnull)request didReceiveResponse:(SKProductsResponse* _Nonnull)response;
@end
