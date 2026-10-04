#import "TFCommon.h"
#include <notify.h>
#include <signal.h>

/* same preference domain as the background service and the Settings pane */
static NSString *const kDomain = @"com.qoij.tunefetch";
static NSString *const kStatusFile = @"/var/mobile/Library/Preferences/com.qoij.tunefetch.status.plist";

id TFPref(NSString *key, id def) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    id v = (id)CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain));
    return v ? v : def;
}

void TFNotify(const char *name) {
    notify_post(name);
}

void TFSetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    TFNotify("com.qoij.tunefetch.reload");
}

NSString *TFToken(void) {
    NSString *t = [NSString stringWithFormat:@"%@", TFPref(@"token", @"")];
    return [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSString *TFBase(void) {
    NSString *h = [NSString stringWithFormat:@"%@", TFPref(@"host", @"")];
    h = [h stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!h.length) return @"";
    while ([h hasSuffix:@"/"]) h = [h substringToIndex:h.length - 1];
    if ([h hasPrefix:@"http://"] || [h hasPrefix:@"https://"]) return h;
    if ([[h componentsSeparatedByString:@":"] count] > 1) return [@"http://" stringByAppendingString:h];
    return [NSString stringWithFormat:@"http://%@:8080", h];
}

NSString *TFEnc(NSString *s) {
    return CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)s, NULL,
        CFSTR("!*'();:@&=+$,/?%#[] \n\r"), kCFStringEncodingUTF8));
}

static void TFRun(NSURLRequest *r, TFDone done) {
    [NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *resp, NSData *d, NSError *e) {
            if (!d || e) { done(nil, @"Can't reach the host"); return; }
            NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
            if (code == 403) { done(nil, @"The host refused the access code. Check it in Settings."); return; }
            if (code != 200) { done(nil, [NSString stringWithFormat:@"The host answered with error %d", (int)code]); return; }
            done([NSJSONSerialization JSONObjectWithData:d options:0 error:nil], nil);
        }];
}

static NSMutableURLRequest *TFRequest(NSString *path, NSTimeInterval timeout, NSString **err) {
    NSString *b = TFBase();
    if (!b.length) { *err = @"Enter the host address in Settings first"; return nil; }
    NSURL *u = [NSURL URLWithString:[b stringByAppendingString:path]];
    if (!u) { *err = @"The host address is not valid"; return nil; }
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout];
    [r setValue:TFToken() forHTTPHeaderField:@"X-TF-Token"];
    return r;
}

void TFGet(NSString *path, NSTimeInterval timeout, TFDone done) {
    NSString *err = nil;
    NSMutableURLRequest *r = TFRequest(path, timeout, &err);
    if (!r) { done(nil, err); return; }
    TFRun(r, done);
}

void TFSend(NSString *path, NSString *body, NSTimeInterval timeout, TFDone done) {
    NSString *err = nil;
    NSMutableURLRequest *r = TFRequest(path, timeout, &err);
    if (!r) { done(nil, err); return; }
    [r setHTTPMethod:@"POST"];
    [r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [r setValue:@"1" forHTTPHeaderField:@"X-TF-App"];
    [r setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    TFRun(r, done);
}

static NSString *TFAgo(NSDate *t) {
    int sec = t ? (int)(-[t timeIntervalSinceNow]) : 0;
    if (sec < 15) return @"just now";
    if (sec < 90) return [NSString stringWithFormat:@"%d s ago", sec];
    if (sec < 5400) return [NSString stringWithFormat:@"%d min ago", (sec + 30) / 60];
    return [NSString stringWithFormat:@"%d h ago", (sec + 1800) / 3600];
}

NSString *TFServiceStatus(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kStatusFile];
    if (!d) return @"has not reported yet. Restart the iPhone if this stays.";
    NSDate *beat = [d objectForKey:@"beat"];
    if (!beat) beat = [d objectForKey:@"time"];
    int pid = [[d objectForKey:@"pid"] intValue];
    BOOL alive = pid > 0 && kill((pid_t)pid, 0) == 0;
    if (!alive || !beat || -[beat timeIntervalSinceNow] > 120) {
        return @"NOT RUNNING. Restart the iPhone to start it again.";
    }
    return [NSString stringWithFormat:@"%@: %@ (%@)", [d objectForKey:@"state"], [d objectForKey:@"msg"], TFAgo([d objectForKey:@"time"])];
}

/* QR payload from the host window: http://HOST:PORT/tunefetch.html#code=ACCESSCODE */
BOOL TFParsePairing(NSString *payload, NSString **host, NSString **code) {
    NSString *p = [payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *u = [NSURL URLWithString:p];
    if (!u || ![[u scheme] hasPrefix:@"http"] || ![[u host] length]) return NO;
    NSString *found = nil;
    for (NSString *kv in [[u fragment] componentsSeparatedByString:@"&"]) {
        if ([kv hasPrefix:@"code="]) found = [kv substringFromIndex:5];
    }
    found = [found stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!found.length || found.length > 64) return NO;
    NSNumber *port = [u port];
    *host = (port && [port intValue] != 8080) ? [NSString stringWithFormat:@"%@:%@", [u host], port] : [u host];
    *code = found;
    return YES;
}

void TFAlert(NSString *title, NSString *msg) {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:title message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [a show];
}
