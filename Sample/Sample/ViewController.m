/* Teak Example -- Copyright (C) 2016 GoCarrot Inc.
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

#import "ViewController.h"
#import <Teak/Teak.h>

@import StoreKit;

@interface ViewController () <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@end

@implementation ViewController

- (void)viewDidLoad {
   [super viewDidLoad];
   // Do any additional setup after loading the view, typically from a nib.
   [[SKPaymentQueue defaultQueue] addTransactionObserver:self];

   [TeakLink registerRoute:@"/alert/:title/:message" name:@"Alert" description:@"Display an alert dialog" block:^(NSDictionary * _Nonnull parameters) {
      UIAlertController * alert = [UIAlertController
                                   alertControllerWithTitle:parameters[@"title"]
                                   message:parameters[@"message"]
                                   preferredStyle:UIAlertControllerStyleAlert];

      UIAlertAction* yesButton = [UIAlertAction
                                  actionWithTitle:@"Sweet"
                                  style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction * action) {
                                     //Handle your yes please button action here
                                  }];
      
      [alert addAction:yesButton];
      [self presentViewController:alert animated:YES completion:nil];
   }];
}

- (void)didReceiveMemoryWarning {
   [super didReceiveMemoryWarning];
   // Dispose of any resources that can be recreated.
}

- (IBAction)makePurchase
{
   //
   SKProductsRequest* productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:@[@"io.teak.demo.angrybots.dollar"]]];

   productsRequest.delegate = self;
   [productsRequest start];
}

- (IBAction)crashApp
{
   //raise (SIGABRT);
   //return;
   NSString* bar = nil;
   NSDictionary* foo = @{
                         @"foo" : bar
                         };
   NSLog(@"%@", foo);
}

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response
{
   if(response.products.count > 0)
   {
      SKProduct* product = [response.products objectAtIndex:0];
      NSLocale* priceLocale = product.priceLocale;
      NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
      NSDecimalNumber* price = product.price;
      NSLog(@"Purchase info: %@ - %@ - %@", product.productIdentifier, currencyCode, price);
      
      SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
      payment.quantity = 1;
      [[SKPaymentQueue defaultQueue] addPayment:payment];
   }
}


- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions
{
   for(SKPaymentTransaction* transaction in transactions)
   {
      if(transaction.transactionState == SKPaymentTransactionStatePurchased ||
         transaction.transactionState == SKPaymentTransactionStateFailed)
      {
         [queue finishTransaction:transaction];
      }
   }
}

- (IBAction)scheduleNotification:(id)sender
{
   TeakNotification* notif = [TeakNotification scheduleNotificationForCreative:@"test" withMessage:@"Test notif" secondsFromNow:10];
   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      while(notif.completed == NO)
      {
         sleep(1);
      }
      NSLog(@"Notification scheduled: %@", notif.teakNotifId);
   });
}


@end
