#import "TFAppDelegate.h"
#import "TFDownloadsVC.h"
#import "TFSettingsVC.h"
#import "TFCommon.h"

@implementation TFAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    TFDownloadsVC *dl = [[TFDownloadsVC alloc] init];
    dl.title = @"Downloads";
    dl.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Downloads" image:nil tag:0];
    TFSettingsVC *st = [[TFSettingsVC alloc] init];
    st.title = @"Settings";
    st.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:nil tag:1];

    UITabBarController *tabs = [[UITabBarController alloc] init];
    tabs.viewControllers = [NSArray arrayWithObjects:
        [[UINavigationController alloc] initWithRootViewController:dl],
        [[UINavigationController alloc] initWithRootViewController:st], nil];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];

    /* first launch: no host yet, so open Settings */
    if ([TFBase() length] == 0) tabs.selectedIndex = 1;
    return YES;
}

@end
