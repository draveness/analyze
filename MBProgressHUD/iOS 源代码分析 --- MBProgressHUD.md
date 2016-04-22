[MBProgressHUD]() 是一个为 iOS app 添加透明浮层 HUD 的第三方框架. 作为一个 UI 层面的框架, 它的实现很简单, 但是其中也有一些非常有意思的代码.

## MBProgressHUD

`MBProgressHUD` 是一个 `UIView` 的子类, 它提供了一系列的创建 `HUD` 的方法. 我们在这里会主要介绍三种使用 `HUD` 的方法.

+ `+ showHUDAddedTo:animated:`
+ `- showAnimated:whileExecutingBlock:onQueue:completionBlock:`
+ `- showWhileExecuting:onTarget:withObject:`

## `+ showHUDAddedTo:animated:`

`MBProgressHUD` 提供了一对类方法 `+ showHUDAddedTo:animated:` 和 `+ hideHUDForView:animated:` 来创建和隐藏 `HUD`, 这是创建和隐藏 `HUD` 最简单的一组方法

```objectivec
+ (MB_INSTANCETYPE)showHUDAddedTo:(UIView *)view animated:(BOOL)animated {
	MBProgressHUD *hud = [[self alloc] initWithView:view];
	hud.removeFromSuperViewOnHide = YES;
	[view addSubview:hud];
	[hud show:animated];
	return MB_AUTORELEASE(hud);
}
```

### `- initWithView:`

首先调用 `+ alloc` `- initWithView:` 方法返回一个 `MBProgressHUD` 的实例, `- initWithView:` 方法会调用当前类的 `- initWithFrame:` 方法.

通过 `- initWithFrame:` 方法的执行, 会为 `MBProgressHUD` 的一些属性设置一系列的默认值. 

```objectivec
- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		// Set default values for properties
		self.animationType = MBProgressHUDAnimationFade;
		self.mode = MBProgressHUDModeIndeterminate;
		...
		// Make it invisible for now
		self.alpha = 0.0f;

		[self registerForKVO];
		...
	}
	return self;
}
```

在 `MBProgressHUD` 初始化的过程中, 有一个需要注意的方法 `- registerForKVO`, 我们会在之后查看该方法的实现.

### `- show:`

在初始化一个 `HUD` 并添加到 `view` 上之后, 这时 `HUD` 并没有显示出来, 因为在初始化时, `view.alpha` 被设置为 0. 所以我们接下来会调用 `- show:` 方法使 `HUD` 显示到屏幕上.

```objectivec
- (void)show:(BOOL)animated {
    NSAssert([NSThread isMainThread], @"MBProgressHUD needs to be accessed on the main thread.");
	useAnimation = animated;
	// If the grace time is set postpone the HUD display
	if (self.graceTime > 0.0) {
        NSTimer *newGraceTimer = [NSTimer timerWithTimeInterval:self.graceTime target:self selector:@selector(handleGraceTimer:) userInfo:nil repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:newGraceTimer forMode:NSRunLoopCommonModes];
        self.graceTimer = newGraceTimer;
	} 
	// ... otherwise show the HUD imediately 
	else {
		[self showUsingAnimation:useAnimation];
	}
}
```

因为在 iOS 开发中, 对于 `UIView` 的处理必须在主线程中, 所以在这里我们要先用 `[NSThread isMainThread]` 来确认当前前程为主线程.

如果 `graceTime` 为 `0`, 那么直接调用 `- showUsingAnimation:` 方法, 否则会创建一个 `newGraceTimer` 当然这个 `timer` 对应的 `selector` 最终调用的也是 `- showUsingAnimation:` 方法.

### `- showUsingAnimation:`

```objectivec
- (void)showUsingAnimation:(BOOL)animated {
    // Cancel any scheduled hideDelayed: calls
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self setNeedsDisplay];

	if (animated && animationType == MBProgressHUDAnimationZoomIn) {
		self.transform = CGAffineTransformConcat(rotationTransform, CGAffineTransformMakeScale(0.5f, 0.5f));
	} else if (animated && animationType == MBProgressHUDAnimationZoomOut) {
		self.transform = CGAffineTransformConcat(rotationTransform, CGAffineTransformMakeScale(1.5f, 1.5f));
	}
	self.showStarted = [NSDate date];
	// Fade in
	if (animated) {
		[UIView beginAnimations:nil context:NULL];
		[UIView setAnimationDuration:0.30];
		self.alpha = 1.0f;
		if (animationType == MBProgressHUDAnimationZoomIn || animationType == MBProgressHUDAnimationZoomOut) {
			self.transform = rotationTransform;
		}
		[UIView commitAnimations];
	}
	else {
		self.alpha = 1.0f;
	}
}
```

这个方法的核心功能就是根据 `animationType` 为 `HUD` 的出现添加合适的动画.

```objectivec
typedef NS_ENUM(NSInteger, MBProgressHUDAnimation) {
	/** Opacity animation */
	MBProgressHUDAnimationFade,
	/** Opacity + scale animation */
	MBProgressHUDAnimationZoom,
	MBProgressHUDAnimationZoomOut = MBProgressHUDAnimationZoom,
	MBProgressHUDAnimationZoomIn
};
```

它在方法刚调用时会通过 `- cancelPreviousPerformRequestsWithTarget:` 移除附加在 `HUD` 上的所有 `selector`, 这样可以保证该方法不会多次调用.

同时也会保存 `HUD` 的出现时间.

```objectivec
self.showStarted = [NSDate date]
```

### `+ hideHUDForView:animated:` 

```objectivec
+ (BOOL)hideHUDForView:(UIView *)view animated:(BOOL)animated {
	MBProgressHUD *hud = [self HUDForView:view];
	if (hud != nil) {
		hud.removeFromSuperViewOnHide = YES;
		[hud hide:animated];
		return YES;
	}
	return NO;
}
```

`+ hideHUDForView:animated:` 方法的实现和 `+ showHUDAddedTo:animated:` 差不多, `+ HUDForView:` 方法会返回对应 `view` 最上层的 `MBProgressHUD` 的实例.

```objectivec
+ (MB_INSTANCETYPE)HUDForView:(UIView *)view {
	NSEnumerator *subviewsEnum = [view.subviews reverseObjectEnumerator];
	for (UIView *subview in subviewsEnum) {
		if ([subview isKindOfClass:self]) {
			return (MBProgressHUD *)subview;
		}
	}
	return nil;
}
```

然后调用的 `- hide:` 方法和 `- hideUsingAnimation:` 方法也没有什么特别的, 只有在 `HUD` 隐藏之后 `- done` 负责隐藏执行 `completionBlock` 和 `delegate` 回调.

```objectivec
- (void)done {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	isFinished = YES;
	self.alpha = 0.0f;
	if (removeFromSuperViewOnHide) {
		[self removeFromSuperview];
	}
#if NS_BLOCKS_AVAILABLE
	if (self.completionBlock) {
		self.completionBlock();
		self.completionBlock = NULL;
	}
#endif
	if ([delegate respondsToSelector:@selector(hudWasHidden:)]) {
		[delegate performSelector:@selector(hudWasHidden:) withObject:self];
	}
}
```

### `- showAnimated:whileExecutingBlock:onQueue:completionBlock:`

> 当 `block` 指定的队列执行时, 显示 `HUD`, 并在 `HUD` 消失时, 调用 `completion`.

同时 `MBProgressHUD` 也提供一些其他的便利方法实现这一功能:

```objectivec
- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block;
- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block completionBlock:(MBProgressHUDCompletionBlock)completion;
- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block onQueue:(dispatch_queue_t)queue;
```

该方法会**异步**在指定 `queue` 上运行 `block` 并在 `block` 执行结束调用 `- cleanUp`.

```
- (void)showAnimated:(BOOL)animated whileExecutingBlock:(dispatch_block_t)block onQueue:(dispatch_queue_t)queue
	 completionBlock:(MBProgressHUDCompletionBlock)completion {
	self.taskInProgress = YES;
	self.completionBlock = completion;
	dispatch_async(queue, ^(void) {
		block();
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			[self cleanUp];
		});
	});
	[self show:animated];
}
```

关于 `- cleanUp` 我们会在下一段中介绍.

### `- showWhileExecuting:onTarget:withObject:`

> 当一个后台任务在新线程中执行时, 显示 `HUD`.

```objectivec
- (void)showWhileExecuting:(SEL)method onTarget:(id)target withObject:(id)object animated:(BOOL)animated {
	methodForExecution = method;
	targetForExecution = MB_RETAIN(target);
	objectForExecution = MB_RETAIN(object);	
	// Launch execution in new thread
	self.taskInProgress = YES;
	[NSThread detachNewThreadSelector:@selector(launchExecution) toTarget:self withObject:nil];
	// Show HUD view
	[self show:animated];
}
```

在保存 `methodForExecution` `targetForExecution` 和 `objectForExecution` 之后, 会在新的线程中调用方法.

```objectivec
- (void)launchExecution {
	@autoreleasepool {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		// Start executing the requested task
		[targetForExecution performSelector:methodForExecution withObject:objectForExecution];
#pragma clang diagnostic pop
		// Task completed, update view in main thread (note: view operations should
		// be done only in the main thread)
		[self performSelectorOnMainThread:@selector(cleanUp) withObject:nil waitUntilDone:NO];
	}
}
```

`- launchExecution` 会创建一个自动释放池, 然后再这个自动释放池中调用方法, 并在方法调用结束之后在主线程执行 `- cleanUp`.

## Trick

在 `MBProgressHUD` 中有很多神奇的魔法来解决一些常见的问题.

### ARC

`MBProgressHUD` 使用了一系列神奇的宏定义来兼容 `MRC`.

```objectivec
#ifndef MB_INSTANCETYPE
#if __has_feature(objc_instancetype)
	#define MB_INSTANCETYPE instancetype
#else
	#define MB_INSTANCETYPE id
#endif
#endif

#ifndef MB_STRONG
#if __has_feature(objc_arc)
	#define MB_STRONG strong
#else
	#define MB_STRONG retain
#endif
#endif

#ifndef MB_WEAK
#if __has_feature(objc_arc_weak)
	#define MB_WEAK weak
#elif __has_feature(objc_arc)
	#define MB_WEAK unsafe_unretained
#else
	#define MB_WEAK assign
#endif
#endif
```

通过宏定义 `__has_feature` 来判断当前环境是否启用了 ARC, 使得不同环境下宏不会出错.

### KVO

`MBProgressHUD` 通过 `@property` 生成了一系列的属性.

```objectivec
- (NSArray *)observableKeypaths {
	return [NSArray arrayWithObjects:@"mode", @"customView", @"labelText", @"labelFont", @"labelColor",
			@"detailsLabelText", @"detailsLabelFont", @"detailsLabelColor", @"progress", @"activityIndicatorColor", nil];
}
```

这些属性在改变的时候不会, 重新渲染整个 `view`,  我们在一般情况下覆写 `setter` 方法, 然后再 `setter` 方法中刷新对应的属性, 在 `MBProgressHUD` 中使用 KVO 来解决这个问题.

```objectivec
- (void)registerForKVO {
	for (NSString *keyPath in [self observableKeypaths]) {
		[self addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:NULL];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (![NSThread isMainThread]) {
		[self performSelectorOnMainThread:@selector(updateUIForKeypath:) withObject:keyPath waitUntilDone:NO];
	} else {
		[self updateUIForKeypath:keyPath];
	}
}

- (void)updateUIForKeypath:(NSString *)keyPath {
	if ([keyPath isEqualToString:@"mode"] || [keyPath isEqualToString:@"customView"] ||
		[keyPath isEqualToString:@"activityIndicatorColor"]) {
		[self updateIndicators];
	} else if ([keyPath isEqualToString:@"labelText"]) {
		label.text = self.labelText;
	} else if ([keyPath isEqualToString:@"labelFont"]) {
		label.font = self.labelFont;
	} else if ([keyPath isEqualToString:@"labelColor"]) {
		label.textColor = self.labelColor;
	} else if ([keyPath isEqualToString:@"detailsLabelText"]) {
		detailsLabel.text = self.detailsLabelText;
	} else if ([keyPath isEqualToString:@"detailsLabelFont"]) {
		detailsLabel.font = self.detailsLabelFont;
	} else if ([keyPath isEqualToString:@"detailsLabelColor"]) {
		detailsLabel.textColor = self.detailsLabelColor;
	} else if ([keyPath isEqualToString:@"progress"]) {
		if ([indicator respondsToSelector:@selector(setProgress:)]) {
			[(id)indicator setValue:@(progress) forKey:@"progress"];
		}
		return;
	}
	[self setNeedsLayout];
	[self setNeedsDisplay];
}
```

`- observeValueForKeyPath:ofObject:change:context:` 方法中的代码是为了保证 UI 的更新一定是在主线程中, 而 `- updateUIForKeypath:` 方法负责 UI 的更新.

## End

`MBProgressHUD` 由于是一个 UI 的第三方库, 所以它的实现还是挺简单的.

<iframe src="http://ghbtns.com/github-btn.html?user=draveness&type=follow&size=large" height="30" width="240" frameborder="0" scrolling="0" style="width:240px; height: 30px;" allowTransparency="true"></iframe>

Blog: [draveness.me](http://draveness.me)


