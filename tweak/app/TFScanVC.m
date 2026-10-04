#import "TFScanVC.h"
#import "TFCommon.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include "quirc.h"

@interface TFScanVC () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation TFScanVC {
    TFScanDone _done;
    AVCaptureSession *_session;
    AVCaptureVideoPreviewLayer *_preview;
    struct quirc *_q;
    int _qw, _qh;
    dispatch_queue_t _queue;
    BOOL _finished;
    CFAbsoluteTime _last;
}

- (id)initWithDone:(TFScanDone)done {
    self = [super init];
    if (self) {
        _done = [done copy];
        self.title = @"Scan QR code";
    }
    return self;
}

- (void)dealloc {
    if (_q) quirc_destroy(_q);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self action:@selector(cancel)];
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 300, 60)];
    hint.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    hint.textColor = [UIColor whiteColor];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.numberOfLines = 3;
    hint.font = [UIFont systemFontOfSize:14];
    hint.text = @"Hold the iPhone about 20 cm from the QR code in the TuneFetch Host window (press \"QR code\" there).";
    hint.tag = 77;
    [self.view addSubview:hint];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _preview.frame = self.view.bounds;
    UIView *hint = [self.view viewWithTag:77];
    hint.frame = CGRectMake(10, self.view.bounds.size.height - 70, self.view.bounds.size.width - 20, 60);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startCamera];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopCamera];
}

- (void)cancel {
    _finished = YES;
    [self stopCamera];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)startCamera {
    if (_session) return;
    AVCaptureDevice *dev = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *in = dev ? [AVCaptureDeviceInput deviceInputWithDevice:dev error:NULL] : nil;
    if (!in) {
        TFAlert(@"No camera", @"The camera is not available. You can type the server address and the access code instead.");
        [self cancel];
        return;
    }
    if ([dev isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus] && [dev lockForConfiguration:NULL]) {
        dev.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        [dev unlockForConfiguration];
    }
    _session = [[AVCaptureSession alloc] init];
    if ([_session canSetSessionPreset:AVCaptureSessionPreset640x480]) _session.sessionPreset = AVCaptureSessionPreset640x480;
    [_session addInput:in];

    AVCaptureVideoDataOutput *out = [[AVCaptureVideoDataOutput alloc] init];
    out.alwaysDiscardsLateVideoFrames = YES;
    /* bi-planar YUV: plane 0 is the grey (luma) image, which is exactly what the decoder wants */
    out.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                                                    forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    _queue = dispatch_queue_create("com.qoij.tunefetch.scan", NULL);
    [out setSampleBufferDelegate:self queue:_queue];
    [_session addOutput:out];

    _preview = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _preview.frame = self.view.bounds;
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:_preview atIndex:0];
    _q = quirc_new();
    _qw = _qh = 0;
    [_session startRunning];
}

- (void)stopCamera {
    if (_session) {
        [_session stopRunning];
        _session = nil;
    }
    [_preview removeFromSuperlayer];
    _preview = nil;
}

- (void)captureOutput:(AVCaptureOutput *)o didOutputSampleBuffer:(CMSampleBufferRef)sb fromConnection:(AVCaptureConnection *)c {
    if (_finished || !_q) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - _last < 0.15) return; /* about 6 frames per second is plenty and keeps an iPhone 4S cool */
    _last = now;
    CVImageBufferRef ib = CMSampleBufferGetImageBuffer(sb);
    if (!ib) return;
    NSString *found = nil;
    CVPixelBufferLockBaseAddress(ib, 0);
    size_t w = CVPixelBufferGetWidthOfPlane(ib, 0);
    size_t h = CVPixelBufferGetHeightOfPlane(ib, 0);
    size_t bpr = CVPixelBufferGetBytesPerRowOfPlane(ib, 0);
    const uint8_t *src = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(ib, 0);
    if (src && w > 0 && h > 0 && w < 8192 && h < 8192) {
        if ((int)w != _qw || (int)h != _qh) {
            if (quirc_resize(_q, (int)w, (int)h) == 0) { _qw = (int)w; _qh = (int)h; }
            else _qw = _qh = 0;
        }
        if (_qw) {
            int bw = 0, bh = 0;
            uint8_t *dst = quirc_begin(_q, &bw, &bh);
            for (size_t y = 0; y < h; y++) memcpy(dst + y * w, src + y * bpr, w);
            quirc_end(_q);
            int n = quirc_count(_q);
            for (int i = 0; i < n && !found; i++) {
                struct quirc_code code;
                struct quirc_data data;
                quirc_extract(_q, i, &code);
                if (quirc_decode(&code, &data) == QUIRC_SUCCESS) {
                    found = [[NSString alloc] initWithBytes:data.payload length:(NSUInteger)data.payload_len encoding:NSUTF8StringEncoding];
                }
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(ib, 0);
    if (found && !_finished) {
        _finished = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self stopCamera];
            [self dismissViewControllerAnimated:YES completion:^{ if (self->_done) self->_done(found); }];
        });
    }
}
@end
