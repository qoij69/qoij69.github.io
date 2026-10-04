#import "TFDownloadsVC.h"
#import "TFCommon.h"
#import <QuartzCore/QuartzCore.h>

/* title shown, yt-dlp format, video height ("" = best), plays on iOS */
static NSArray *TFFormats(void) {
    return [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"MP3", @"mp3", @"", @"1", nil],
        [NSArray arrayWithObjects:@"M4A (AAC)", @"m4a", @"", @"1", nil],
        [NSArray arrayWithObjects:@"AAC", @"aac", @"", @"1", nil],
        [NSArray arrayWithObjects:@"WAV (lossless)", @"wav", @"", @"1", nil],
        [NSArray arrayWithObjects:@"FLAC (lossless)", @"flac", @"", @"0", nil],
        [NSArray arrayWithObjects:@"OPUS", @"opus", @"", @"0", nil],
        [NSArray arrayWithObjects:@"OGG Vorbis", @"ogg", @"", @"0", nil],
        [NSArray arrayWithObjects:@"MP4 video 720p", @"mp4", @"720", @"1", nil],
        [NSArray arrayWithObjects:@"MP4 video 1080p", @"mp4", @"1080", @"1", nil],
        [NSArray arrayWithObjects:@"MKV video (best)", @"mkv", @"", @"0", nil],
        [NSArray arrayWithObjects:@"WEBM video (best)", @"webm", @"", @"0", nil], nil];
}

@implementation TFDownloadsVC {
    NSArray *_jobs;
    UILabel *_conn;
    UITextView *_tv;
    UILabel *_hint;
    UIButton *_fmtBtn;
    NSInteger _fmtIndex;
    UIActionSheet *_fmtSheet;
    UIButton *_add;
    NSTimer *_timer;
    NSMutableArray *_sheetActions;
    NSDictionary *_sheetJob;
}

- (id)init {
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(clearFinished)];

    UIView *head = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 208)];
    head.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    _conn = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 300, 30)];
    _conn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _conn.backgroundColor = [UIColor clearColor];
    _conn.font = [UIFont systemFontOfSize:12];
    _conn.textColor = [UIColor grayColor];
    _conn.numberOfLines = 2;
    _conn.text = @"Connecting to the host...";
    [head addSubview:_conn];

    _tv = [[UITextView alloc] initWithFrame:CGRectMake(10, 40, 300, 80)];
    _tv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _tv.font = [UIFont systemFontOfSize:15];
    _tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _tv.autocorrectionType = UITextAutocorrectionTypeNo;
    _tv.keyboardType = UIKeyboardTypeURL;
    _tv.delegate = self;
    _tv.layer.borderWidth = 1;
    _tv.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    _tv.layer.cornerRadius = 6;
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    bar.barStyle = UIBarStyleBlack;
    bar.translucent = YES;
    bar.items = [NSArray arrayWithObjects:
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(hideKeyboard)], nil];
    _tv.inputAccessoryView = bar;
    [head addSubview:_tv];

    _hint = [[UILabel alloc] initWithFrame:CGRectMake(18, 48, 280, 40)];
    _hint.backgroundColor = [UIColor clearColor];
    _hint.font = [UIFont systemFontOfSize:14];
    _hint.textColor = [UIColor lightGrayColor];
    _hint.numberOfLines = 2;
    _hint.text = @"Paste links or type song names, one per line";
    _hint.userInteractionEnabled = NO;
    [head addSubview:_hint];

    _fmtIndex = [TFPref(@"fmtChoice", @0) integerValue];
    if (_fmtIndex < 0 || _fmtIndex >= (NSInteger)[TFFormats() count]) _fmtIndex = 0;
    _fmtBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _fmtBtn.frame = CGRectMake(10, 128, 300, 32);
    _fmtBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_fmtBtn addTarget:self action:@selector(pickFormat) forControlEvents:UIControlEventTouchUpInside];
    [self updateFormatTitle];
    [head addSubview:_fmtBtn];

    _add = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _add.frame = CGRectMake(10, 166, 300, 38);
    _add.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_add setTitle:@"Add to queue" forState:UIControlStateNormal];
    [_add addTarget:self action:@selector(addJobs) forControlEvents:UIControlEventTouchUpInside];
    [head addSubview:_add];

    self.tableView.tableHeaderView = head;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
    _timer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)hideKeyboard {
    [_tv resignFirstResponder];
}

- (void)textViewDidChange:(UITextView *)tv {
    _hint.hidden = tv.text.length > 0;
}

- (void)updateFormatTitle {
    NSArray *f = [TFFormats() objectAtIndex:_fmtIndex];
    [_fmtBtn setTitle:[NSString stringWithFormat:@"Format: %@  (tap to change)", [f objectAtIndex:0]] forState:UIControlStateNormal];
}

- (void)pickFormat {
    [_tv resignFirstResponder];
    _fmtSheet = [[UIActionSheet alloc] initWithTitle:@"Download as" delegate:self cancelButtonTitle:nil
                              destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSArray *f in TFFormats()) [_fmtSheet addButtonWithTitle:[f objectAtIndex:0]];
    [_fmtSheet addButtonWithTitle:@"Cancel"];
    _fmtSheet.cancelButtonIndex = _fmtSheet.numberOfButtons - 1;
    [_fmtSheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)addJobs {
    [_tv resignFirstResponder];
    NSString *text = [_tv.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) { TFAlert(@"Nothing to add", @"Paste a link or type a song name first."); return; }
    NSArray *f = [TFFormats() objectAtIndex:_fmtIndex];
    NSString *fmt = [f objectAtIndex:1], *res = [f objectAtIndex:2];
    BOOL video = [fmt isEqualToString:@"mp4"] || [fmt isEqualToString:@"mkv"] || [fmt isEqualToString:@"webm"];
    NSMutableString *body = [NSMutableString stringWithFormat:@"url=%@&fmt=%@&meta=1", TFEnc(text), fmt];
    if (res.length) [body appendFormat:@"&res=%@", res];
    if (!video && [TFPref(@"cover", @YES) boolValue]) [body appendString:@"&cover=1"];
    if (![TFPref(@"playlists", @NO) boolValue]) [body appendString:@"&pl=single"];
    _add.enabled = NO;
    TFSend(@"/api/add", body, 15, ^(id json, NSString *err) {
        self->_add.enabled = YES;
        if (err) { TFAlert(@"Could not add", err); return; }
        self->_tv.text = @"";
        self->_hint.hidden = NO;
        [self refresh];
    });
}

- (void)clearFinished {
    TFSend(@"/api/clear", @"x=1", 10, ^(id json, NSString *err) {
        if (err) TFAlert(@"Could not clear", err);
        [self refresh];
    });
}

- (void)refresh {
    TFGet(@"/api/jobs", 5, ^(id json, NSString *err) {
        if ([json isKindOfClass:[NSArray class]]) {
            self->_jobs = [[(NSArray *)json reverseObjectEnumerator] allObjects];
            [self.tableView reloadData];
        }
    });
    TFGet(@"/api/ping", 5, ^(id json, NSString *err) {
        if (![json isKindOfClass:[NSDictionary class]]) {
            self->_conn.textColor = [UIColor redColor];
            self->_conn.text = err ? err : @"Host not reachable";
            return;
        }
        NSDictionary *p = json;
        id auth = [p objectForKey:@"auth"];
        if ([auth isKindOfClass:[NSNumber class]] && ![auth boolValue]) {
            self->_conn.textColor = [UIColor redColor];
            self->_conn.text = @"Host found, but the access code is wrong or missing (see Settings)";
            return;
        }
        NSString *line = [NSString stringWithFormat:@"Connected - %d downloading, %d waiting",
                          [[p objectForKey:@"active"] intValue], [[p objectForKey:@"queued"] intValue]];
        NSArray *devs = [p objectForKey:@"devices"];
        if ([devs isKindOfClass:[NSArray class]] && devs.count) {
            NSDictionary *d = [devs objectAtIndex:0];
            line = [line stringByAppendingFormat:@"\niPhone: %@, %d sent, %d to go", [d objectForKey:@"status"],
                    [[d objectForKey:@"sent"] intValue], [[d objectForKey:@"pending"] intValue]];
        } else {
            line = [line stringByAppendingString:@"\niPhone has not checked in yet (see Settings)"];
        }
        self->_conn.textColor = [UIColor grayColor];
        self->_conn.text = line;
    });
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return _jobs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"job"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"job"];
    NSDictionary *j = [_jobs objectAtIndex:ip.row];
    NSString *st = [j objectForKey:@"status"];
    NSMutableString *d = [NSMutableString stringWithFormat:@"%@ - %@", [[j objectForKey:@"fmt"] uppercaseString], st];
    if ([st isEqualToString:@"Downloading"] || [st isEqualToString:@"Converting"]) {
        [d appendFormat:@" %d%%", [[j objectForKey:@"pct"] intValue]];
        NSString *sp = [j objectForKey:@"speed"];
        if ([sp length]) [d appendFormat:@"  %@", sp];
    }
    NSString *er = [j objectForKey:@"err"];
    if ([st isEqualToString:@"Failed"] && [er length]) [d appendFormat:@" - %@", er];
    c.textLabel.text = [j objectForKey:@"title"];
    c.textLabel.font = [UIFont systemFontOfSize:15];
    c.detailTextLabel.text = d;
    c.detailTextLabel.textColor = [st isEqualToString:@"Failed"] ? [UIColor redColor] :
                                  [st isEqualToString:@"Done"] ? [UIColor colorWithRed:0.1 green:0.5 blue:0.1 alpha:1] : [UIColor grayColor];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *j = [_jobs objectAtIndex:ip.row];
    NSString *st = [j objectForKey:@"status"];
    UIActionSheet *sh = [[UIActionSheet alloc] initWithTitle:[j objectForKey:@"title"] delegate:self
                                           cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    _sheetActions = [NSMutableArray array];
    _sheetJob = j;
    if ([st isEqualToString:@"Queued"] || [st isEqualToString:@"Starting"] || [st isEqualToString:@"Downloading"] || [st isEqualToString:@"Converting"]) {
        [sh addButtonWithTitle:@"Cancel download"];
        [_sheetActions addObject:@"cancel"];
    }
    if ([st isEqualToString:@"Failed"] || [st isEqualToString:@"Canceled"]) {
        [sh addButtonWithTitle:@"Try again"];
        [_sheetActions addObject:@"retry"];
    }
    [sh addButtonWithTitle:@"Close"];
    sh.cancelButtonIndex = sh.numberOfButtons - 1;
    [sh showFromTabBar:self.tabBarController.tabBar];
}

- (void)actionSheet:(UIActionSheet *)sh clickedButtonAtIndex:(NSInteger)i {
    if (sh == _fmtSheet) {
        if (i < 0 || i >= (NSInteger)[TFFormats() count]) return;
        _fmtIndex = i;
        TFSetPref(@"fmtChoice", [NSNumber numberWithInteger:i]);
        [self updateFormatTitle];
        NSArray *f = [TFFormats() objectAtIndex:i];
        if ([[f objectAtIndex:3] isEqualToString:@"0"] && [TFPref(@"playable", @YES) boolValue]) {
            TFAlert(@"Heads up", [NSString stringWithFormat:@"iOS 6 cannot play %@. With \"Only formats iOS plays\" on (Settings), the host will not send these files to the iPhone. Turn it off if you still want them.", [f objectAtIndex:0]]);
        }
        return;
    }
    if (i < 0 || i >= (NSInteger)_sheetActions.count) return;
    NSString *act = [_sheetActions objectAtIndex:i];
    NSString *path = [act isEqualToString:@"cancel"] ? @"/api/cancel" : @"/api/retry";
    TFSend(path, [NSString stringWithFormat:@"id=%@", [_sheetJob objectForKey:@"id"]], 10, ^(id json, NSString *err) {
        [self refresh];
    });
}

@end
