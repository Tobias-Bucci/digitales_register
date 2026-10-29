#import "OpenFilePlugin.h"

@interface OpenFilePlugin ()<UIDocumentInteractionControllerDelegate>
@end

static NSString *const CHANNEL_NAME = @"open_file";

@implementation OpenFilePlugin{
    FlutterResult _result;
    UIViewController *_viewController;
    UIDocumentInteractionController *_documentController;
    UIDocumentInteractionController *_interactionController;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:CHANNEL_NAME
                                     binaryMessenger:[registrar messenger]];
    UIViewController *viewController =
    [UIApplication sharedApplication].delegate.window.rootViewController;
    OpenFilePlugin* instance = [[OpenFilePlugin alloc] initWithViewController:viewController];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];
    if (self) {
        _viewController = viewController;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"open_file" isEqualToString:call.method]) {
        if (_result != nil) {
            // One document controller is shown at a time; the pending call
            // completes when it is dismissed.
            result([self resultJsonWithType:-4 message:@"Another file is still being opened."]);
            return;
        }
        NSString *msg = call.arguments[@"file_path"];
        if(msg==nil){
            result([self resultJsonWithType:-4 message:@"the file path cannot be null"]);
            return;
        }
        NSFileManager *fileManager=[NSFileManager defaultManager];
        BOOL fileExist=[fileManager fileExistsAtPath:msg];
        if(fileExist){
            //            NSURL *resourceToOpen = [NSURL fileURLWithPath:msg];
//            NSString *exestr = [[msg pathExtension] lowercaseString];
            _documentController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:msg]];
            _documentController.delegate = self;
            NSString *uti = call.arguments[@"uti"];
            BOOL isBlank = [self isBlankString:uti];
            if(!isBlank){
                _documentController.UTI = uti;
            }
//             else{
//                 if([exestr isEqualToString:@"rtf"]){
//                     _documentController.UTI=@"public.rtf";
//                 }else if([exestr isEqualToString:@"txt"]){
//                     _documentController.UTI=@"public.plain-text";
//                 }else if([exestr isEqualToString:@"html"]||
//                          [exestr isEqualToString:@"htm"]){
//                     _documentController.UTI=@"public.html";
//                 }else if([exestr isEqualToString:@"xml"]){
//                     _documentController.UTI=@"public.xml";
//                 }else if([exestr isEqualToString:@"tar"]){
//                     _documentController.UTI=@"public.tar-archive";
//                 }else if([exestr isEqualToString:@"gz"]||
//                          [exestr isEqualToString:@"gzip"]){
//                     _documentController.UTI=@"org.gnu.gnu-zip-archive";
//                 }else if([exestr isEqualToString:@"tgz"]){
//                     _documentController.UTI=@"org.gnu.gnu-zip-tar-archive";
//                 }else if([exestr isEqualToString:@"jpg"]||
//                          [exestr isEqualToString:@"jpeg"]){
//                     _documentController.UTI=@"public.jpeg";
//                 }else if([exestr isEqualToString:@"png"]){
//                     _documentController.UTI=@"public.png";
//                 }else if([exestr isEqualToString:@"avi"]){
//                     _documentController.UTI=@"public.avi";
//                 }else if([exestr isEqualToString:@"mpg"]||
//                          [exestr isEqualToString:@"mpeg"]){
//                     _documentController.UTI=@"public.mpeg";
//                 }else if([exestr isEqualToString:@"mp4"]){
//                     _documentController.UTI=@"public.mpeg-4";
//                 }else if([exestr isEqualToString:@"3gpp"]||
//                          [exestr isEqualToString:@"3gp"]){
//                     _documentController.UTI=@"public.3gpp";
//                 }else if([exestr isEqualToString:@"mp3"]){
//                     _documentController.UTI=@"public.mp3";
//                 }else if([exestr isEqualToString:@"zip"]){
//                     _documentController.UTI=@"com.pkware.zip-archive";
//                 }else if([exestr isEqualToString:@"gif"]){
//                     _documentController.UTI=@"com.compuserve.gif";
//                 }else if([exestr isEqualToString:@"bmp"]){
//                     _documentController.UTI=@"com.microsoft.bmp";
//                 }else if([exestr isEqualToString:@"ico"]){
//                     _documentController.UTI=@"com.microsoft.ico";
//                 }else if([exestr isEqualToString:@"doc"]){
//                     _documentController.UTI=@"com.microsoft.word.doc";
//                 }else if([exestr isEqualToString:@"xls"]){
//                     _documentController.UTI=@"com.microsoft.excel.xls";
//                 }else if([exestr isEqualToString:@"ppt"]){
//                     _documentController.UTI=@"com.microsoft.powerpoint.​ppt";
//                 }else if([exestr isEqualToString:@"wav"]){
//                     _documentController.UTI=@"com.microsoft.waveform-​audio";
//                 }else if([exestr isEqualToString:@"wm"]){
//                     _documentController.UTI=@"com.microsoft.windows-​media-wm";
//                 }else if([exestr isEqualToString:@"wmv"]){
//                     _documentController.UTI=@"com.microsoft.windows-​media-wmv";
//                 }else if([exestr isEqualToString:@"pdf"]){
//                     _documentController.UTI=@"com.adobe.pdf";
//                 }else {
//                     NSLog(@"doc type not supported for preview");
//                     NSLog(@"%@", exestr);
//                 }
//             }
            // The dismissal delegates complete this call once a preview or
            // menu is shown; every other path completes it right here.
            _result = result;
            @try {
                BOOL previewSucceeded = [_documentController presentPreviewAnimated:YES];
                if(!previewSucceeded){
                    BOOL menuSucceeded = [_documentController presentOpenInMenuFromRect:CGRectMake(500,20,100,100) inView:[UIApplication sharedApplication].delegate.window.rootViewController.view animated:YES];
                    if(!menuSucceeded){
                        [self finishWithType:-1 message:@"No APP found to open this file。"];
                    }
                }
            }@catch (NSException *exception) {
                [self finishWithType:-4 message:@"File opened incorrectly。"];
            }
        }else{
            result([self resultJsonWithType:-2 message:@"the file does not exist"]);
        }
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (NSString *)resultJsonWithType:(int)type message:(NSString *)message {
    NSDictionary * dict = @{@"message":message, @"type":@(type)};
    NSData * jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

/// Completes the pending open_file call exactly once so the next call can
/// start. The controller stays referenced: after the Open In menu closes it
/// may still be handing the file to the chosen app.
- (void)finishWithType:(int)type message:(NSString *)message {
    FlutterResult result = _result;
    _result = nil;
    if (result != nil) {
        result([self resultJsonWithType:type message:message]);
    }
}

- (void)documentInteractionControllerDidEndPreview:(UIDocumentInteractionController *)controller {
    [self finishWithType:0 message:@"done"];
}

- (void)documentInteractionControllerDidDismissOpenInMenu:(UIDocumentInteractionController *)controller {
    [self finishWithType:0 message:@"done"];
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return [UIApplication sharedApplication].delegate.window.rootViewController;
}

- (BOOL) isBlankString:(NSString *)string {
    if (string == nil || string == NULL) {
        return YES;
    }
    if ([string isKindOfClass:[NSNull class]]) {
        return YES;
    }
    if ([[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length]==0){
        return YES;
    }
    return NO;
}
@end
