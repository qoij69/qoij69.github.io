#import <UIKit/UIKit.h>

typedef void (^TFScanDone)(NSString *payload);

/* Camera screen that reads a QR code (decoded with the bundled quirc library) and hands the text to the caller. */
@interface TFScanVC : UIViewController
- (id)initWithDone:(TFScanDone)done;
@end
