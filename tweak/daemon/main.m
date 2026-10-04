#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdarg.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <notify.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <pthread.h>

#define RECV_PORT 8081
#define MAX_CONN 4

static NSString *const APP = @"com.qoij.tunefetch";
static NSString *const STATUS = @"/var/mobile/Library/Preferences/com.qoij.tunefetch.status.plist";
static NSString *const PIDF = @"/var/mobile/Library/Caches/com.qoij.tunefetchd.pid";
static NSString *const LOGF = @"/var/mobile/Library/Caches/tunefetchd.log";

static id pref(NSString *k, id d) {
    id v = (id)CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)APP));
    return v ? v : d;
}

static NSString *trim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *tokenPref(void) {
    return trim([NSString stringWithFormat:@"%@", pref(@"token", @"")]);
}

static NSString *baseFor(NSString *h) {
    h = trim(h);
    while ([h hasSuffix:@"/"]) h = [h substringToIndex:h.length - 1];
    if ([h hasPrefix:@"http://"] || [h hasPrefix:@"https://"]) return h;
    if ([[h componentsSeparatedByString:@":"] count] > 1) return [@"http://" stringByAppendingString:h];
    return [NSString stringWithFormat:@"http://%@:8080", h];
}

static BOOL onWifi(void) {
    struct sockaddr_in z;
    bzero(&z, sizeof z);
    z.sin_len = sizeof z;
    z.sin_family = AF_INET;
    SCNetworkReachabilityRef r = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&z);
    SCNetworkReachabilityFlags f = 0;
    BOOL ok = r && SCNetworkReachabilityGetFlags(r, &f);
    if (r) CFRelease(r);
    return ok && (f & kSCNetworkReachabilityFlagsReachable) && !(f & kSCNetworkReachabilityFlagsIsWWAN);
}

/* ---------- log and status ---------- */

static void tflog(const char *fmt, ...) {
    char ts[32];
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    strftime(ts, sizeof ts, "%H:%M:%S", &tmv);
    fprintf(stderr, "%s ", ts);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    fflush(stderr);
}

static pthread_mutex_t gMutex = PTHREAD_MUTEX_INITIALIZER; /* not @synchronized: that needs SjLj unwinding symbols this SDK lacks */
static NSString *gState = @"Starting";
static NSString *gMsg = @"";
static NSDate *gTime;

static void flushStatus(void) {
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
        gState, @"state", gMsg, @"msg", gTime ? gTime : [NSDate date], @"time", [NSDate date], @"beat",
        [NSNumber numberWithInt:(int)getpid()], @"pid", nil];
    [d writeToFile:STATUS atomically:YES];
}

static void setStatus(NSString *state, NSString *msg) {
    pthread_mutex_lock(&gMutex);
    gState = state;
    gMsg = msg;
    gTime = [NSDate date];
    flushStatus();
    pthread_mutex_unlock(&gMutex);
    tflog("%s: %s", [state UTF8String], [msg UTF8String]);
}

/* ---------- receiver: the host PC pushes files here ---------- */

static void reply(int fd, int code, const char *text) {
    char out[240];
    int n = snprintf(out, sizeof out, "HTTP/1.0 %d %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
                     code, text, (int)strlen(text), text);
    send(fd, out, (size_t)n, 0);
}

/* every part between slashes must be a real name: no empty part, no "." and no ".." (a name like "Wait... what.mp3" is fine) */
static BOOL validRelPath(NSString *p) {
    if (!p.length || [p hasPrefix:@"/"] || [p length] > 1000) return NO;
    for (NSString *c in [p componentsSeparatedByString:@"/"]) {
        if (!c.length || [c isEqualToString:@"."] || [c isEqualToString:@".."]) return NO;
    }
    return YES;
}

static NSString *headerValue(const char *buf, const char *name) {
    char key[64];
    snprintf(key, sizeof key, "\r\n%s:", name);
    const char *h = strcasestr(buf, key);
    if (!h) return nil;
    const char *v = h + strlen(key);
    const char *e = strstr(v, "\r\n");
    NSString *s = e ? [[NSString alloc] initWithBytes:v length:(NSUInteger)(e - v) encoding:NSUTF8StringEncoding]
                    : [NSString stringWithUTF8String:v];
    return s ? trim(s) : nil;
}

static volatile int gPartCounter = 0;

static void handle(int fd) {
    struct timeval tv;
    tv.tv_sec = 20;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
    @autoreleasepool {
        CFPreferencesAppSynchronize((__bridge CFStringRef)APP);
        if (![pref(@"enabled", @YES) boolValue]) { reply(fd, 403, "sync is off"); return; }

        char buf[8192];
        size_t total = 0;
        char *end = NULL;
        while (total < sizeof buf - 1) {
            ssize_t n = recv(fd, buf + total, sizeof buf - 1 - total, 0);
            if (n <= 0) break;
            total += (size_t)n;
            buf[total] = 0;
            end = strstr(buf, "\r\n\r\n");
            if (end) break;
        }
        if (!end) { reply(fd, 400, "bad request"); return; }
        size_t hlen = (size_t)(end - buf) + 4;
        *end = 0; /* from here buf holds only the header text */

        /* access code: the PC must send the same code that is set in the app */
        NSString *want = tokenPref();
        if (!want.length) {
            reply(fd, 403, "no access code on the iPhone");
            setStatus(@"Setup", @"Enter the access code from the host window in Settings");
            return;
        }
        NSString *got = headerValue(buf, "X-TF-Token");
        if (!got || ![got isEqualToString:want]) {
            reply(fd, 403, "wrong access code");
            setStatus(@"Error", @"The PC sent a wrong access code. Check it in Settings.");
            return;
        }

        char method[8] = "";
        char target[2048] = "";
        if (sscanf(buf, "%7s %2047s", method, target) != 2 || strcmp(method, "PUT") != 0 || strncmp(target, "/put/", 5) != 0) {
            reply(fd, 400, "bad request");
            return;
        }
        NSString *cls = headerValue(buf, "Content-Length");
        long long len = cls ? atoll([cls UTF8String]) : -1;
        if (len < 0) { reply(fd, 411, "length required"); return; }

        NSString *name = [[NSString stringWithUTF8String:target + 5] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSSet *okExt = [NSSet setWithObjects:@"mp3", @"m4a", @"aac", @"wav", @"mp4", @"m4v", @"flac", @"ogg", @"opus", @"mkv", @"webm", nil];
        if (!validRelPath(name) || ![okExt containsObject:[[name pathExtension] lowercaseString]]) {
            tflog("refused file name: %s", target + 5);
            reply(fd, 400, "bad name");
            return;
        }
        NSString *dest = [NSString stringWithFormat:@"%@", pref(@"dest", @"/var/mobile/Media/music")];
        BOOL destOK = [dest hasPrefix:@"/var/mobile/"];
        for (NSString *c in [dest componentsSeparatedByString:@"/"]) if ([c isEqualToString:@".."]) destOK = NO;
        if (!destOK) { reply(fd, 403, "bad folder"); setStatus(@"Error", @"The save folder must be inside /var/mobile/"); return; }

        NSString *final = [dest stringByAppendingPathComponent:name];
        int pc = __sync_add_and_fetch(&gPartCounter, 1);
        NSString *part = [final stringByAppendingFormat:@".%d.part", pc];
        [[NSFileManager defaultManager] createDirectoryAtPath:[final stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        int out = open([part fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (out < 0) { reply(fd, 500, "cannot write"); setStatus(@"Error", @"Can't write to the save folder"); return; }

        BOOL ok = YES;
        long long got2 = 0;
        size_t have = total - hlen;
        if (have > (size_t)len) have = (size_t)len;
        if (have && write(out, buf + hlen, have) != (ssize_t)have) ok = NO;
        got2 = (long long)have;
        tv.tv_sec = 30;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        char chunk[16384];
        while (ok && got2 < len) {
            size_t w = (size_t)(len - got2);
            if (w > sizeof chunk) w = sizeof chunk;
            ssize_t n = recv(fd, chunk, w, 0);
            if (n <= 0) { ok = NO; break; }
            if (write(out, chunk, (size_t)n) != n) { ok = NO; break; }
            got2 += n;
        }
        close(out);
        if (!ok || got2 != len || rename([part fileSystemRepresentation], [final fileSystemRepresentation]) != 0) {
            unlink([part fileSystemRepresentation]);
            reply(fd, 400, "incomplete");
            setStatus(@"Error", @"A file from the PC arrived incomplete");
            return;
        }
        reply(fd, 200, "ok");
        setStatus(@"Online", [NSString stringWithFormat:@"Received %@", [name lastPathComponent]]);
    }
}

static void serve(void) {
    dispatch_semaphore_t slots = dispatch_semaphore_create(MAX_CONN);
    for (;;) {
        int s = socket(AF_INET, SOCK_STREAM, 0);
        int one = 1;
        struct sockaddr_in a;
        if (s >= 0) setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
        bzero(&a, sizeof a);
        a.sin_len = sizeof a;
        a.sin_family = AF_INET;
        a.sin_addr.s_addr = htonl(INADDR_ANY);
        a.sin_port = htons(RECV_PORT);
        if (s < 0 || bind(s, (struct sockaddr *)&a, sizeof a) < 0 || listen(s, 8) < 0) {
            tflog("cannot listen on port %d (%s), retrying", RECV_PORT, strerror(errno));
            if (s >= 0) close(s);
            sleep(10);
            continue;
        }
        tflog("listening on port %d", RECV_PORT);
        for (;;) {
            struct sockaddr_in c;
            socklen_t l = sizeof c;
            int fd = accept(s, (struct sockaddr *)&c, &l);
            if (fd < 0) {
                if (errno == EINTR) continue;
                break;
            }
            if (dispatch_semaphore_wait(slots, DISPATCH_TIME_NOW) != 0) { reply(fd, 503, "busy"); close(fd); continue; }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                handle(fd);
                close(fd);
                dispatch_semaphore_signal(slots);
            });
        }
        close(s);
        sleep(2);
    }
}

/* ---------- check-in: tells the host where this phone is, so it can push new files ---------- */

@interface TFSync : NSObject
- (void)start;
- (void)schedule:(NSTimeInterval)s;
@end

static void reachChanged(SCNetworkReachabilityRef t, SCNetworkReachabilityFlags f, void *info) {
    /* Wi-Fi came back (for example after the iPhone woke up): check in soon */
    if (f & kSCNetworkReachabilityFlagsReachable) [(__bridge TFSync *)info schedule:3];
}

@implementation TFSync {
    NSTimeInterval _interval;
    BOOL _busy;
    int _fails;
    SCNetworkReachabilityRef _reach;
}

- (void)start {
    int t1, t2;
    notify_register_dispatch("com.qoij.tunefetch.sync", &t1, dispatch_get_main_queue(), ^(int x) { [self schedule:0]; });
    notify_register_dispatch("com.qoij.tunefetch.reload", &t2, dispatch_get_main_queue(), ^(int x) { [self schedule:2]; });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ serve(); });

    struct sockaddr_in z;
    bzero(&z, sizeof z);
    z.sin_len = sizeof z;
    z.sin_family = AF_INET;
    _reach = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&z);
    if (_reach) {
        SCNetworkReachabilityContext ctx = {0, (__bridge void *)self, NULL, NULL, NULL};
        SCNetworkReachabilitySetCallback(_reach, reachChanged, &ctx);
        SCNetworkReachabilityScheduleWithRunLoop(_reach, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    }
    [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(beat) userInfo:nil repeats:YES];
    setStatus(@"Starting", @"Background service started");
    [self schedule:3];
}

- (void)beat {
    pthread_mutex_lock(&gMutex);
    flushStatus();
    pthread_mutex_unlock(&gMutex);
}

- (void)schedule:(NSTimeInterval)s {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(tick) object:nil];
    [self performSelector:@selector(tick) withObject:nil afterDelay:s];
}

- (void)retryAfterFailure {
    _fails++;
    NSTimeInterval d = 15.0 * (double)(1 << (_fails > 3 ? 3 : _fails - 1)); /* 15, 30, 60, 120 s */
    [self schedule:MIN(_interval, d)];
}

- (void)tick {
    if (_busy) return;
    CFPreferencesAppSynchronize((__bridge CFStringRef)APP);
    _interval = [pref(@"interval", @300) doubleValue];
    if (_interval < 30) _interval = 300;
    if (![pref(@"enabled", @YES) boolValue]) { setStatus(@"Off", @"Sync is turned off"); [self schedule:_interval]; return; }
    NSString *host = trim([NSString stringWithFormat:@"%@", pref(@"host", @"")]);
    if (!host.length) { setStatus(@"Setup", @"Enter the server address in Settings"); [self schedule:_interval]; return; }
    NSString *token = tokenPref();
    if (!token.length) { setStatus(@"Setup", @"Enter the access code from the host window in Settings"); [self schedule:_interval]; return; }
    if ([pref(@"wifionly", @YES) boolValue] && !onWifi()) { setStatus(@"Waiting", @"Waiting for Wi-Fi"); [self schedule:MIN(_interval, 60)]; return; }
    NSURL *url = [NSURL URLWithString:[baseFor(host) stringByAppendingString:@"/api/device"]];
    if (!url) { setStatus(@"Setup", @"The server address is not valid"); [self schedule:_interval]; return; }

    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10];
    [r setHTTPMethod:@"POST"];
    [r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [r setValue:token forHTTPHeaderField:@"X-TF-Token"];
    [r setHTTPBody:[[NSString stringWithFormat:@"port=%d&playable=%d", RECV_PORT, [pref(@"playable", @YES) boolValue] ? 1 : 0]
                    dataUsingEncoding:NSUTF8StringEncoding]];
    _busy = YES;
    [NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *resp, NSData *d, NSError *e) {
            self->_busy = NO;
            NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
            id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            if (code == 403) {
                setStatus(@"Error", @"The host refused the access code. Check it in Settings.");
                [self retryAfterFailure];
                return;
            }
            if (!d || e) {
                NSString *why = e ? [e localizedDescription] : @"no answer";
                setStatus(@"Offline", [NSString stringWithFormat:@"Can't reach the host (%@)", why]);
                [self retryAfterFailure];
                return;
            }
            if (code != 200 || ![j isKindOfClass:[NSDictionary class]] || ![[j objectForKey:@"ok"] boolValue]) {
                setStatus(@"Offline", [NSString stringWithFormat:@"The host answered with error %d", (int)code]);
                [self retryAfterFailure];
                return;
            }
            self->_fails = 0;
            int pend = [[j objectForKey:@"pending"] intValue];
            setStatus(@"Online", pend > 0 ? [NSString stringWithFormat:@"Host is sending %d file(s)", pend] : @"Up to date");
            /* while files are on the way, check in more often: it keeps the host pushing and recovers from a short Wi-Fi drop */
            [self schedule:pend > 0 ? MIN(self->_interval, 30) : self->_interval];
        }];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        if (access([LOGF fileSystemRepresentation], F_OK) == 0) {
            off_t sz = 0;
            FILE *f = fopen([LOGF fileSystemRepresentation], "r");
            if (f) { fseeko(f, 0, SEEK_END); sz = ftello(f); fclose(f); }
            if (sz > 200000) unlink([LOGF fileSystemRepresentation]);
        }
        freopen([LOGF fileSystemRepresentation], "a", stderr);
        [[NSString stringWithFormat:@"%d", getpid()] writeToFile:PIDF atomically:YES encoding:NSUTF8StringEncoding error:nil];
        tflog("tunefetchd started (pid %d)", getpid());
        TFSync *s = [[TFSync alloc] init];
        [s start];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
