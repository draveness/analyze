//
//  PINRemoteImageCategory.h
//  Pods
//
//  Created by Garrett Moon on 11/4/14.
//
//

#if PIN_TARGET_IOS
#import <UIKit/UIKit.h>
#elif PIN_TARGET_MAC
#import <Cocoa/Cocoa.h>
#endif

#import "PINRemoteImageManager.h"

@protocol PINRemoteImageCategory;

/**
 PINRemoteImageCategoryManager is a class that handles subclassing image display classes. PINImage+PINRemoteImage, UIButton+PINRemoteImage, etc, all delegate their work to this class. If you'd like to create a category to display an image on a view, you should mimic one of the above categories.
 */

@interface PINRemoteImageCategoryManager : NSObject

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
               fromURL:(nullable NSURL *)url;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
               fromURL:(nullable NSURL *)url
      placeholderImage:(nullable PINImage *)placeholderImage;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
               fromURL:(nullable NSURL *)url
      placeholderImage:(nullable PINImage *)placeholderImage
            completion:(nullable PINRemoteImageManagerImageCompletion)completion;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
               fromURL:(nullable NSURL *)url
            completion:(nullable PINRemoteImageManagerImageCompletion)completion;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
               fromURL:(nullable NSURL *)url
          processorKey:(nullable NSString *)processorKey
             processor:(nullable PINRemoteImageManagerImageProcessor)processor;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
               fromURL:(nullable NSURL *)url
      placeholderImage:(nullable PINImage *)placeholderImage
          processorKey:(nullable NSString *)processorKey
             processor:(nullable PINRemoteImageManagerImageProcessor)processor;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
               fromURL:(nullable NSURL *)url
          processorKey:(nullable NSString *)processorKey
             processor:(nullable PINRemoteImageManagerImageProcessor)processor
            completion:(nullable PINRemoteImageManagerImageCompletion)completion;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
              fromURLs:(nullable NSArray <NSURL *> *)urls
      placeholderImage:(nullable PINImage *)placeholderImage
          processorKey:(nullable NSString *)processorKey
             processor:(nullable PINRemoteImageManagerImageProcessor)processor
            completion:(nullable PINRemoteImageManagerImageCompletion)completion;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
              fromURLs:(nullable NSArray <NSURL *> *)urls;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
              fromURLs:(nullable NSArray <NSURL *> *)urls
      placeholderImage:(nullable PINImage *)placeholderImage;

+ (void)setImageOnView:(nonnull id <PINRemoteImageCategory>)view
              fromURLs:(nullable NSArray <NSURL *> *)urls
      placeholderImage:(nullable PINImage *)placeholderImage
            completion:(nullable PINRemoteImageManagerImageCompletion)completion;

+ (void)cancelImageDownloadOnView:(nonnull id <PINRemoteImageCategory>)view;

+ (nullable NSUUID *)downloadImageOperationUUIDOnView:(nonnull id <PINRemoteImageCategory>)view;

+ (void)setDownloadImageOperationUUID:(nullable NSUUID *)downloadImageOperationUUID onView:(nonnull id <PINRemoteImageCategory>)view;

+ (BOOL)updateWithProgressOnView:(nonnull id <PINRemoteImageCategory>)view;

+ (void)setUpdateWithProgressOnView:(BOOL)updateWithProgress onView:(nonnull id <PINRemoteImageCategory>)view;

@end

/**
 Protocol to implement on UIView subclasses to support PINRemoteImage
 */
@protocol PINRemoteImageCategory <NSObject>

//Call manager

/**
 Set the image from the given URL.
 
 @param url NSURL to fetch from.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url;

/**
 Set the image from the given URL and set placeholder image while image at URL is being retrieved.
 
 @param url NSURL to fetch from.
 @param placeholderImage PINImage to set on the view while the image at URL is being retrieved.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url placeholderImage:(nullable PINImage *)placeholderImage;

/**
 Set the image from the given URL and call completion when finished.
 
 @param url NSURL to fetch from.
 @param completion Called when url has been retrieved and set on view.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url completion:(nullable PINRemoteImageManagerImageCompletion)completion;

/**
 Set the image from the given URL, set placeholder while image at url is being retrieved and call completion when finished.
 
 @param url NSURL to fetch from.
 @param placeholderImage PINImage to set on the view while the image at URL is being retrieved.
 @param completion Called when url has been retrieved and set on view.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url placeholderImage:(nullable PINImage *)placeholderImage completion:(nullable PINRemoteImageManagerImageCompletion)completion;

/**
 Retrieve the image from the given URL, process it using the passed in processor block and set result on view.
 
 @param url NSURL to fetch from.
 @param processorKey NSString key to uniquely identify processor. Used in caching.
 @param processor PINRemoteImageManagerImageProcessor processor block which should return the processed image.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url processorKey:(nullable NSString *)processorKey processor:(nullable PINRemoteImageManagerImageProcessor)processor;

/**
 Set placeholder on view and retrieve the image from the given URL, process it using the passed in processor block and set result on view.
 
 @param url NSURL to fetch from.
 @param placeholderImage PINImage to set on the view while the image at URL is being retrieved.
 @param processorKey NSString key to uniquely identify processor. Used in caching.
 @param processor PINRemoteImageManagerImageProcessor processor block which should return the processed image.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url placeholderImage:(nullable PINImage *)placeholderImage processorKey:(nullable NSString *)processorKey processor:(nullable PINRemoteImageManagerImageProcessor)processor;

/**
 Retrieve the image from the given URL, process it using the passed in processor block and set result on view. Call completion after image has been fetched, processed and set on view.
 
 @param url NSURL to fetch from.
 @param processorKey NSString key to uniquely identify processor. Used in caching.
 @param processor PINRemoteImageManagerImageProcessor processor block which should return the processed image.
 @param completion Called when url has been retrieved and set on view.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url processorKey:(nullable NSString *)processorKey processor:(nullable PINRemoteImageManagerImageProcessor)processor completion:(nullable PINRemoteImageManagerImageCompletion)completion;

/**
 Set placeholder on view and retrieve the image from the given URL, process it using the passed in processor block and set result on view. Call completion after image has been fetched, processed and set on view.
 
 @param url NSURL to fetch from.
 @param placeholderImage PINImage to set on the view while the image at URL is being retrieved.
 @param processorKey NSString key to uniquely identify processor. Used in caching.
 @param processor PINRemoteImageManagerImageProcessor processor block which should return the processed image.
 @param completion Called when url has been retrieved and set on view.
 */
- (void)pin_setImageFromURL:(nullable NSURL *)url placeholderImage:(nullable PINImage *)placeholderImage processorKey:(nullable NSString *)processorKey processor:(nullable PINRemoteImageManagerImageProcessor)processor completion:(nullable PINRemoteImageManagerImageCompletion)completion;

/**
 Retrieve one of the images at the passed in URLs depending on previous network performance and set result on view.
 
 @param urls NSArray of NSURLs sorted in increasing quality
 */
- (void)pin_setImageFromURLs:(nullable NSArray <NSURL *> *)urls;

/**
 Set placeholder on view and retrieve one of the images at the passed in URLs depending on previous network performance and set result on view.
 
 @param urls NSArray of NSURLs sorted in increasing quality
 @param placeholderImage PINImage to set on the view while the image at URL is being retrieved.
 */
- (void)pin_setImageFromURLs:(nullable NSArray <NSURL *> *)urls placeholderImage:(nullable PINImage *)placeholderImage;

/**
 Set placeholder on view and retrieve one of the images at the passed in URLs depending on previous network performance and set result on view. Call completion after image has been fetched and set on view.
 
 @param urls NSArray of NSURLs sorted in increasing quality
 @param placeholderImage PINImage to set on the view while the image at URL is being retrieved.
 @param completion Called when url has been retrieved and set on view.
 */
- (void)pin_setImageFromURLs:(nullable NSArray <NSURL *> *)urls placeholderImage:(nullable PINImage *)placeholderImage completion:(nullable PINRemoteImageManagerImageCompletion)completion;

/**
 Cancels the image download. Guarantees that previous setImage calls will *not* have their results set on the image view after calling this (as opposed to PINRemoteImageManager which does not guarantee cancellation).
 */
- (void)pin_cancelImageDownload;

/**
 Returns the NSUUID associated with any PINRemoteImage task currently running on the view.
 
 @return NSUUID associated with any PINRemoteImage task currently running on the view.
 */
- (nullable NSUUID *)pin_downloadImageOperationUUID;

/**
 Set the current NSUUID associated with a PINRemoteImage task running on the view.
 
 @param downloadImageOperationUUID NSUUID associated with a PINRemoteImage task.
 */
- (void)pin_setDownloadImageOperationUUID:(nullable NSUUID *)downloadImageOperationUUID;

/**
 Whether the view should update with progress images (such as those provided by progressive JPEG images).
 
 @return BOOL value indicating whether the view should update with progress images
 */
@property (nonatomic, assign) BOOL pin_updateWithProgress;

//Handle
- (void)pin_setPlaceholderWithImage:(nullable PINImage *)image;
- (void)pin_updateUIWithRemoteImageManagerResult:(nonnull PINRemoteImageManagerResult *)result;
- (void)pin_clearImages;
- (BOOL)pin_ignoreGIFs;

@optional

- (PINRemoteImageManagerDownloadOptions)pin_defaultOptions;

@end
