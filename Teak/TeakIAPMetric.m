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

#import "TeakIAPMetric.h"

@interface TeakIAPMetric () <SKProductsRequestDelegate>

@property (strong, nonatomic) NSDictionary* payload;
@property (strong, nonatomic) SKProductsRequest* request;
@property (nonatomic, copy) void (^removeBlock)();

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response;

@end

@implementation TeakIAPMetric

+ (void)sendTransaction:(SKPaymentTransaction*)transaction withPayload:(NSDictionary*)payload
{
   static NSMutableArray* referenceHolder = nil;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      referenceHolder = [[NSMutableArray alloc] init];
   });

   TeakIAPMetric* metric = [[TeakIAPMetric alloc] init];
   metric.payload = payload;

   metric.request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:@[transaction.payment.productIdentifier]]];
   metric.request.delegate = metric;

   [referenceHolder addObject:metric];
   __weak TeakIAPMetric* weakSelf = metric;
   metric.removeBlock = ^{
      [referenceHolder removeObject:weakSelf];
   };

   [metric.request start];
}

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response
{
   for(SKProduct* product in response.products)
   {
      NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:self.payload];

      [payload setObject:[NSNumber numberWithInt:product.price.doubleValue * 100]
                  forKey:@"amount"];
      [payload setObject:[product.priceLocale objectForKey:NSLocaleCurrencyCode]
                  forKey:@"currency_code"];

      // TODO: Send out metric
   }

   self.removeBlock();
}

@end
