#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>

#if PICKER_MEDIA && (__has_include(<PhotosUI/PHPicker.h>) || __has_include("PHPicker.h"))
#define PHPicker
#import <PhotosUI/PHPicker.h>
#endif

#if defined(PICKER_MEDIA) && !defined(PHPicker)
#error This file_picker requires PHPicker (iOS 14+).
#endif

@interface FilePickerPlugin : NSObject<FlutterPlugin, FlutterStreamHandler, UITabBarDelegate, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate
#ifdef PICKER_MEDIA
#ifdef PHPicker
    , PHPickerViewControllerDelegate
#endif
#endif // PICKER_MEDIA
#ifdef PICKER_DOCUMENT
    , UIDocumentPickerDelegate
#endif // PICKER_DOCUMENT
#ifdef PICKER_AUDIO
    , MPMediaPickerControllerDelegate
#endif // PICKER_AUDIO
>
@end
