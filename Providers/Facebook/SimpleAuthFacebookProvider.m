//
//  SimpleAuthFacebookProvider.m
//  SimpleAuth
//
//  Created by Caleb Davenport on 11/6/13.
//  Copyright (c) 2013 Seesaw Decisions Corporation. All rights reserved.
//

#import "SimpleAuthFacebookProvider.h"

#import <SAMCategories/NSDictionary+SAMAdditions.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

@implementation SimpleAuthFacebookProvider

#pragma mark - NSObject

+ (void)initialize {
    [SimpleAuth registerProviderClass:self];
}


#pragma mark - SimpleAuthProvider

+ (NSString *)type {
    return @"facebook";
}


+ (NSDictionary *)defaultOptions {
    return @{
        @"permissions" : @[ @"email" ]
    };
}


- (void)authorizeWithCompletion:(SimpleAuthRequestHandler)completion {
    [[[self systemAccount]
     flattenMap:^RACStream *(ACAccount *account) {
         NSArray *signals = @[
             [self remoteAccountWithSystemAccount:account],
             [RACSignal return:account]
         ];
         return [self rac_liftSelector:@selector(dictionaryWithRemoteAccount:systemAccount:) withSignalsFromArray:signals];
     }]
     subscribeNext:^(NSDictionary *response) {
         completion(response, nil);
     }
     error:^(NSError *error) {
         completion(nil, error);
     }];
}


#pragma mark - Private

- (RACSignal *)systemAccounts {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        ACAccountStore *store = [[self class] accountStore];
        ACAccountType *type = [store accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierFacebook];
        NSDictionary *options = @{
            ACFacebookAppIdKey : self.options[@"app_id"],
            ACFacebookPermissionsKey : self.options[@"permissions"]
        };
        [store requestAccessToAccountsWithType:type options:options completion:^(BOOL granted, NSError *error) {
            if (granted) {
                NSArray *accounts = [store accountsWithAccountType:type];
                NSUInteger numberOfAccounts = [accounts count];
                if (numberOfAccounts == 0) {
                    error = (error ?: [[NSError alloc] initWithDomain:ACErrorDomain code:ACErrorAccountNotFound userInfo:nil]);
                    [subscriber sendError:error];
                }
                else {
                    [subscriber sendNext:accounts];
                    [subscriber sendCompleted];
                }
            }
            else {
                error = (error ?: [[NSError alloc] initWithDomain:ACErrorDomain code:ACErrorPermissionDenied userInfo:nil]);
                [subscriber sendError:error];
            }
        }];
        return nil;
    }];
}


- (RACSignal *)systemAccount {
    return [[self systemAccounts] flattenMap:^RACStream *(NSArray *accounts) {
        ACAccount *account = [accounts lastObject];
        return [RACSignal return:account];
    }];
}


- (RACSignal *)remoteAccountWithSystemAccount:(ACAccount *)account {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        NSURL *URL = [NSURL URLWithString:@"https://graph.facebook.com/me"];
        SLRequest *request = [SLRequest requestForServiceType:SLServiceTypeFacebook requestMethod:SLRequestMethodGET URL:URL parameters:nil];
        request.account = account;
        [request performRequestWithHandler:^(NSData *data, NSHTTPURLResponse *response, NSError *connectionError) {
            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 99)];
            NSInteger statusCode = [response statusCode];
            if ([indexSet containsIndex:statusCode] && data) {
                NSError *parseError = nil;
                NSDictionary *dictionary = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&parseError];
                if (dictionary) {
                    [subscriber sendNext:dictionary];
                    [subscriber sendCompleted];
                }
                else {
                    [subscriber sendError:parseError];
                }
            }
            else {
                [subscriber sendError:connectionError];
            }
        }];
        return nil;
    }];
}


- (NSDictionary *)dictionaryWithRemoteAccount:(NSDictionary *)remoteAccount systemAccount:(ACAccount *)systemAccount {
    NSMutableDictionary *dictionary = [NSMutableDictionary new];
    
    // Provider
    dictionary[@"provider"] = [[self class] type];
    
    // Credentials
    dictionary[@"credentials"] = @{
        @"token" : systemAccount.credential.oauthToken
    };
    
    // User ID
    dictionary[@"uid"] = remoteAccount[@"id"];
    
    // Raw response
    dictionary[@"extra"] = @{
        @"raw_info" : remoteAccount,
        @"account" : systemAccount
    };
    
    // Profile image
    NSString *avatar = [NSString stringWithFormat:@"https://graph.facebook.com/%@/picture?type=large", remoteAccount[@"id"]];
    
    // Location
    NSString *location = remoteAccount[@"location"][@"name"];
    
    // User info
    NSMutableDictionary *user = [NSMutableDictionary new];
    user[@"nickname"] = remoteAccount[@"username"];
    user[@"email"] = remoteAccount[@"email"];
    user[@"name"] = remoteAccount[@"name"];
    user[@"first_name"] = remoteAccount[@"first_name"];
    user[@"last_name"] = remoteAccount[@"last_name"];
    user[@"image"] = avatar;
    if (location) {
        user[@"location"] = location;
    }
    user[@"verified"] = remoteAccount[@"verified"];
    user[@"urls"] = @{
        @"Facebook" : remoteAccount[@"link"],
    };
    dictionary[@"info"] = user;
    
    return dictionary;
}

@end
