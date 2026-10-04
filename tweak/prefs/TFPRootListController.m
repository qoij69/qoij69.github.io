#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#include <notify.h>

static NSString *const APP = @"com.qoij.tunefetch";
static NSString *const STATUS = @"/var/mobile/Library/Preferences/com.qoij.tunefetch.status.plist";

static NSString *pv(NSString *k, NSString *d) {
    id v = (id)CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)APP));
    return v ? [NSString stringWithFormat:@"%@", v] : d;
}

static NSString *baseFor(NSString *h) {
    h = [h stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([h hasSuffix:@"/"]) h = [h substringToIndex:h.length - 1];
    if ([h hasPrefix:@"http://"] || [h hasPrefix:@"https://"]) return h;
    if ([[h componentsSeparatedByString:@":"] count] > 1) return [@"http://" stringByAppendingString:h];
    return [NSString stringWithFormat:@"http://%@:8080", h];
}

@interface TFPRootListController : PSListController
@end

@implementation TFPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    [self refreshFooter];
    return _specifiers;
}

- (void)refreshFooter {
    NSDictionary *st = [NSDictionary dictionaryWithContentsOfFile:STATUS];
    NSString *txt = @"Status: no sync yet";
    if (st) {
        NSDateFormatter *f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"HH:mm:ss";
        txt = [NSString stringWithFormat:@"Status: %@ (%@)", [st objectForKey:@"msg"], [f stringFromDate:[st objectForKey:@"time"]]];
    }
    for (PSSpecifier *s in _specifiers)
        if ([[s propertyForKey:@"id"] isEqual:@"statusGroup"]) [s setProperty:txt forKey:@"footerText"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (void)alert:(NSString *)t msg:(NSString *)m {
    [[[UIAlertView alloc] initWithTitle:t message:m delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)syncNow {
    notify_post("com.qoij.tunefetch.sync");
    [self alert:@"Sync started" msg:@"The background service is checking the server now."];
}

- (void)testConnection {
    CFPreferencesAppSynchronize((__bridge CFStringRef)APP);
    NSString *host = pv(@"host", @"");
    if (!host.length) { [self alert:@"No server" msg:@"Enter the server address first."]; return; }
    NSURL *u = [NSURL URLWithString:[baseFor(host) stringByAppendingString:@"/api/ping"]];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:5];
    [r setValue:pv(@"token", @"") forHTTPHeaderField:@"X-TF-Token"];
    [NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *resp, NSData *d, NSError *e) {
            NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            id auth = [j isKindOfClass:[NSDictionary class]] ? [j objectForKey:@"auth"] : nil;
            if ([auth isKindOfClass:[NSNumber class]] && ![auth boolValue])
                [self alert:@"Wrong access code" msg:@"The host is running, but it did not accept the access code. Enter the code shown in the host window."];
            else if ([j isKindOfClass:[NSDictionary class]] && [[j objectForKey:@"ok"] boolValue])
                [self alert:@"Backend ONLINE" msg:[NSString stringWithFormat:@"Connected to TuneFetch Host.\nSaving to: %@", [j objectForKey:@"out"]]];
            else
                [self alert:@"Backend OFFLINE" msg:@"Could not reach the server. Check the address and Wi-Fi, and that the host is started on the PC."];
        }];
}
@end
