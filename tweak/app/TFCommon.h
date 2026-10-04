#import <UIKit/UIKit.h>

typedef void (^TFDone)(id json, NSString *err);

id TFPref(NSString *key, id def);
void TFSetPref(NSString *key, id value);
void TFNotify(const char *name);
NSString *TFBase(void);
NSString *TFToken(void);
NSString *TFEnc(NSString *s);
void TFGet(NSString *path, NSTimeInterval timeout, TFDone done);
void TFSend(NSString *path, NSString *body, NSTimeInterval timeout, TFDone done);
NSString *TFServiceStatus(void);
BOOL TFParsePairing(NSString *payload, NSString **host, NSString **code);
void TFAlert(NSString *title, NSString *msg);
