#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"
#import "BaiduMobStat.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
 
//  [[BaiduMobStat defaultStat] setEnableExceptionLog:YES]; //Crash日志收集
  [[BaiduMobStat defaultStat] startWithAppId:@"63183f3fc2"];
  // Override point for customization after application launch.
  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

@end

