//
//  ViewController.m
//  Sample
//
//  Created by Pat Wilson on 2/24/16.
//  Copyright © 2016 GoCarrot Inc. All rights reserved.
//

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
