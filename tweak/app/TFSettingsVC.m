#import "TFSettingsVC.h"
#import "TFCommon.h"
#import "TFScanVC.h"

/* sections: 0 host, 1 this iPhone, 2 downloads, 3 service */
static NSArray *TFIntervals(void) {
    return [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:[NSNumber numberWithInt:60], @"1 minute", nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:300], @"5 minutes", nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:900], @"15 minutes", nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:1800], @"30 minutes", nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:3600], @"1 hour", nil], nil];
}

static NSString *TFIntervalTitle(void) {
    int cur = [TFPref(@"interval", @300) intValue];
    for (NSArray *i in TFIntervals()) if ([[i objectAtIndex:0] intValue] == cur) return [i objectAtIndex:1];
    return [NSString stringWithFormat:@"%d s", cur];
}

@implementation TFSettingsVC {
    UILabel *_statusLabel;
    NSTimer *_timer;
}

- (id)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateStatus];
    _timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(updateStatus) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
    [self.view endEditing:YES];
}

- (void)updateStatus {
    _statusLabel.text = [@"Background service: " stringByAppendingString:TFServiceStatus()];
}

#pragma mark - structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 4 : s == 1 ? 4 : s == 2 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"Host (your PC)" : s == 1 ? @"This iPhone" : s == 2 ? @"Downloads" : @"Syncing";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"Easiest: press \"QR code\" in the host window and scan it here. Or type the PC's IP address (for example 192.168.1.23) and the access code.";
    if (s == 1) return @"The host sends finished songs into this folder (it must be inside /var/mobile).";
    return nil;
}

- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    if (s != 3) return nil;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 84)];
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 4, 280, 78)];
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.textColor = [UIColor colorWithRed:0.3 green:0.33 blue:0.4 alpha:1];
    _statusLabel.font = [UIFont systemFontOfSize:13];
    _statusLabel.numberOfLines = 5;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    [v addSubview:_statusLabel];
    [self updateStatus];
    return v;
}

- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s {
    return s == 3 ? 90 : s == 0 ? 66 : s == 1 ? 52 : 12;
}

#pragma mark - cells

- (UITableViewCell *)fieldCell:(NSString *)label key:(NSString *)key tag:(int)tag placeholder:(NSString *)ph def:(NSString *)def {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.text = label;
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(100, 12, 185, 22)];
    f.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    f.tag = tag;
    f.delegate = self;
    f.text = [NSString stringWithFormat:@"%@", TFPref(key, def)];
    f.placeholder = ph;
    f.font = [UIFont systemFontOfSize:15];
    f.textColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.55 alpha:1];
    f.keyboardType = (tag == 3) ? UIKeyboardTypeASCIICapable : UIKeyboardTypeURL;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    [c.contentView addSubview:f];
    return c;
}

- (UITableViewCell *)switchCell:(NSString *)label key:(NSString *)key tag:(int)tag def:(BOOL)def {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.text = label;
    c.textLabel.font = [UIFont boldSystemFontOfSize:15];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.tag = tag;
    sw.on = [TFPref(key, [NSNumber numberWithBool:def]) boolValue];
    [sw addTarget:self action:@selector(switched:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}

- (UITableViewCell *)buttonCell:(NSString *)label {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.textLabel.text = label;
    c.textLabel.textAlignment = NSTextAlignmentCenter;
    c.textLabel.textColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.55 alpha:1];
    return c;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger s = ip.section, r = ip.row;
    if (s == 0 && r == 0) return [self buttonCell:@"Scan QR code from the host"];
    if (s == 0 && r == 1) return [self fieldCell:@"Server" key:@"host" tag:1 placeholder:@"192.168.1.23" def:@""];
    if (s == 0 && r == 2) return [self fieldCell:@"Code" key:@"token" tag:3 placeholder:@"from the host window" def:@""];
    if (s == 0 && r == 3) return [self buttonCell:@"Test connection"];
    if (s == 1 && r == 0) return [self fieldCell:@"Save to" key:@"dest" tag:2 placeholder:@"/var/mobile/Media/music" def:@"/var/mobile/Media/music"];
    if (s == 1 && r == 1) return [self switchCell:@"Only formats iOS plays" key:@"playable" tag:11 def:YES];
    if (s == 1 && r == 2) return [self switchCell:@"Wi-Fi only" key:@"wifionly" tag:12 def:YES];
    if (s == 1 && r == 3) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        c.textLabel.text = @"Check in every";
        c.textLabel.font = [UIFont boldSystemFontOfSize:15];
        c.detailTextLabel.text = TFIntervalTitle();
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (s == 2 && r == 0) return [self switchCell:@"Embed cover art" key:@"cover" tag:13 def:YES];
    if (s == 2 && r == 1) return [self switchCell:@"Whole playlists" key:@"playlists" tag:14 def:NO];
    return [self buttonCell:@"Sync now"];
}

#pragma mark - actions

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self.view endEditing:YES];
    if (ip.section == 0 && ip.row == 0) {
        [self scan];
    } else if (ip.section == 0 && ip.row == 3) {
        [self testConnection];
    } else if (ip.section == 1 && ip.row == 3) {
        UIActionSheet *sh = [[UIActionSheet alloc] initWithTitle:@"Check in with the host every" delegate:self
                                               cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        for (NSArray *i in TFIntervals()) [sh addButtonWithTitle:[i objectAtIndex:1]];
        [sh addButtonWithTitle:@"Cancel"];
        sh.cancelButtonIndex = sh.numberOfButtons - 1;
        [sh showFromTabBar:self.tabBarController.tabBar];
    } else if (ip.section == 3) {
        TFNotify("com.qoij.tunefetch.sync");
        /* check in from the app too: it shows the real answer (or the real error) right away */
        NSString *body = [NSString stringWithFormat:@"port=8081&playable=%d", [TFPref(@"playable", @YES) boolValue] ? 1 : 0];
        TFSend(@"/api/device", body, 10, ^(id json, NSString *err) {
            [self updateStatus];
            if (![json isKindOfClass:[NSDictionary class]]) { TFAlert(@"Host not reachable", err ? err : @"The host did not answer."); return; }
            int pend = [[json objectForKey:@"pending"] intValue];
            NSString *m = pend > 0 ? [NSString stringWithFormat:@"The host has %d file(s) for this iPhone and is sending them now.", pend]
                                   : @"The host has nothing new for this iPhone.";
            TFAlert(@"Connected", [NSString stringWithFormat:@"%@\n\nBackground service: %@", m, TFServiceStatus()]);
        });
    }
}

- (void)testConnection {
        TFGet(@"/api/ping", 6, ^(id json, NSString *err) {
            if (![json isKindOfClass:[NSDictionary class]]) { TFAlert(@"Not connected", err ? err : @"The host did not answer."); return; }
            NSDictionary *p = json;
            id auth = [p objectForKey:@"auth"];
            if ([auth isKindOfClass:[NSNumber class]] && ![auth boolValue]) {
                TFAlert(@"Wrong access code", @"The host is running, but it did not accept the access code. Enter the code shown in the host window.");
                return;
            }
            id yt = [p objectForKey:@"yt_dlp"];
            NSString *m = [NSString stringWithFormat:@"The host is running.\nyt-dlp: %@\nSaving on the PC to: %@",
                           [yt isKindOfClass:[NSString class]] ? yt : @"still starting", [p objectForKey:@"out"]];
            TFAlert(@"Connected", m);
        });
}

- (void)scan {
    TFScanVC *sc = [[TFScanVC alloc] initWithDone:^(NSString *payload) { [self pairWith:payload]; }];
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:sc];
    nc.navigationBar.barStyle = UIBarStyleBlack;
    [self presentViewController:nc animated:YES completion:nil];
}

- (void)pairWith:(NSString *)payload {
    NSString *host = nil, *code = nil;
    if (!TFParsePairing(payload, &host, &code)) {
        TFAlert(@"Not a TuneFetch code", @"This QR code does not come from the TuneFetch Host.");
        return;
    }
    TFSetPref(@"host", host);
    TFSetPref(@"token", code);
    [self.tableView reloadData];
    [self testConnection];
}

- (void)actionSheet:(UIActionSheet *)sh clickedButtonAtIndex:(NSInteger)i {
    NSArray *all = TFIntervals();
    if (i < 0 || i >= (NSInteger)all.count) return;
    TFSetPref(@"interval", [[all objectAtIndex:i] objectAtIndex:0]);
    [self.tableView reloadData];
}

- (void)switched:(UISwitch *)sw {
    NSString *key = sw.tag == 11 ? @"playable" : sw.tag == 12 ? @"wifionly" : sw.tag == 13 ? @"cover" : @"playlists";
    TFSetPref(key, [NSNumber numberWithBool:sw.on]);
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    [f resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)f {
    NSString *v = [f.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (f.tag == 1) {
        TFSetPref(@"host", v);
    } else if (f.tag == 3) {
        TFSetPref(@"token", v);
    } else if (f.tag == 2) {
        if (!v.length) v = @"/var/mobile/Media/music";
        if (![v hasPrefix:@"/var/mobile/"]) {
            TFAlert(@"Folder not allowed", @"The save folder must be inside /var/mobile/. Reset to the default.");
            v = @"/var/mobile/Media/music";
            f.text = v;
        }
        TFSetPref(@"dest", v);
    }
}

@end
