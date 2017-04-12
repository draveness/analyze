//
//  ViewController.m
//  Layout
//
//  Created by Draveness on 8/28/16.
//  Copyright © 2016 Draveness. All rights reserved.
//

#import "ViewController.h"

#import <Masonry/Masonry.h>

@interface ViewController ()

@end

@implementation ViewController {
    UITextField *_textField;
    UILabel *_indicateLabel;
    NSMutableArray *_views;

    NSMutableDictionary *_resultDictionary;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _views = [[NSMutableArray alloc] init];

    UIButton *autoLayoutButton = [[UIButton alloc] init];
    [autoLayoutButton setTitle:@"AutoLayout" forState:UIControlStateNormal];
    [autoLayoutButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [autoLayoutButton addTarget:self action:@selector(generateViews)
     forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:autoLayoutButton];
    [autoLayoutButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(20);
        make.bottom.mas_equalTo(0);
    }];

    UIButton *nestedButton = [[UIButton alloc] init];
    [nestedButton setTitle:@"Nested" forState:UIControlStateNormal];
    [nestedButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [nestedButton addTarget:self action:@selector(generateNestedViews)
     forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:nestedButton];
    [nestedButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(20);
        make.bottom.mas_equalTo(0);
    }];

    UIButton *frameButton = [[UIButton alloc] init];
    [frameButton setTitle:@"Frame" forState:UIControlStateNormal];
    [frameButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [frameButton addTarget:self action:@selector(generateFrameViews) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:frameButton];
    [frameButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(20);
        make.bottom.mas_equalTo(0);
    }];

    [@[autoLayoutButton, nestedButton, frameButton] mas_distributeViewsAlongAxis:MASAxisTypeHorizontal
                                                             withFixedItemLength:140 leadSpacing:0 tailSpacing:0];

    _textField = [[UITextField alloc] init];
    _textField.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_textField];
    [_textField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(20);
        make.right.mas_equalTo(-20);
        make.bottom.mas_equalTo(autoLayoutButton.mas_top);
        make.height.mas_equalTo(20);
    }];

    _indicateLabel = [[UILabel alloc] init];
    _indicateLabel.textColor = [UIColor blackColor];
    _indicateLabel.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:_indicateLabel];
    [_indicateLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.top.mas_equalTo(0);
        make.height.mas_equalTo(20);
    }];

    UIButton *printResult = [[UIButton alloc] init];
    [printResult setTitle:@"PrintResult" forState:UIControlStateNormal];
    [printResult setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [printResult addTarget:self action:@selector(printerResult) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:printResult];
    [printResult mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.mas_equalTo(20);
        make.top.left.mas_equalTo(0);
        make.width.mas_equalTo(100);
    }];

    _resultDictionary = [[NSMutableDictionary alloc] init];
    [_resultDictionary setObject:[[NSMutableDictionary alloc] init] forKey:@"AutoLayout"];
    [_resultDictionary setObject:[[NSMutableDictionary alloc] init] forKey:@"NestedAutoLayout"];
    [_resultDictionary setObject:[[NSMutableDictionary alloc] init] forKey:@"Frame"];
    [_resultDictionary setObject:[[NSMutableDictionary alloc] init] forKey:@"ASDK"];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_textField becomeFirstResponder];
}

- (void)generateViews {
    NSInteger number = _textField.text.integerValue;
    for (UIView *view in _views) {
        [view removeFromSuperview];
    }
    _views = [[NSMutableArray alloc] init];

    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    for (NSInteger i = 0; i < number; i++) {
        UIView *leftView = self.view;
        UIView *topView = self.view;
        if (_views.count != 0) {
            NSInteger left = arc4random() % _views.count;
            NSInteger top = arc4random() % _views.count;
            leftView = _views[left];
            topView = _views[top];
        }

        CGFloat hue = ( arc4random() % 256 / 256.0 );  //  0.0 to 1.0
        CGFloat saturation = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from white
        CGFloat brightness = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from black
        UIColor *color = [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];

        NSInteger leftSpace = (arc4random() % 414) - (int)leftView.frame.origin.x;
        NSInteger topSpace = (arc4random() % 568) - (int)topView.frame.origin.y;

        UIView *newView = [[UIView alloc] init];
        newView.backgroundColor = color;
        [self.view addSubview:newView];
        [newView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.mas_greaterThanOrEqualTo(0);
            make.right.mas_lessThanOrEqualTo(0);
            make.top.mas_greaterThanOrEqualTo(20);
            make.bottom.mas_lessThanOrEqualTo(-40);
            make.left.mas_equalTo(leftView).offset(leftSpace).priorityMedium();
            make.top.mas_equalTo(topView).offset(topSpace).priorityMedium();
            make.size.mas_equalTo(10);
        }];

        [_views addObject:newView];
    }
    NSTimeInterval endTime = [NSDate timeIntervalSinceReferenceDate];

    NSTimeInterval timeInterval = endTime - startTime;

    NSMutableDictionary *autoLayoutDictionary = _resultDictionary[@"AutoLayout"];
    NSMutableDictionary *currentTimesDictionary = autoLayoutDictionary[@(number)] ?: [[NSMutableDictionary alloc] init];
    NSNumber *times = currentTimesDictionary[@"times"] ? : @0;
    NSNumber *avgTime = currentTimesDictionary[@"avgTime"] ? : @0;
    currentTimesDictionary[@"avgTime"] = @((times.integerValue * avgTime.doubleValue + timeInterval) / (double)(times.integerValue + 1));
    currentTimesDictionary[@"times"] = @(times.integerValue + 1);
    [autoLayoutDictionary setObject:currentTimesDictionary forKey:@(number)];

    _indicateLabel.text = [NSString stringWithFormat:@"%ld: %f", (long)number, endTime-startTime];
}

- (void)generateFrameViews {
    NSInteger number = _textField.text.integerValue;
    for (UIView *view in _views) {
        [view removeFromSuperview];
    }
    _views = [[NSMutableArray alloc] init];

    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    for (NSInteger i = 0; i < number; i++) {
        CGFloat hue = ( arc4random() % 256 / 256.0 );  //  0.0 to 1.0
        CGFloat saturation = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from white
        CGFloat brightness = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from black
        UIColor *color = [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];

        NSInteger leftSpace = (arc4random() % 404) % (int)self.view.frame.size.width;
        NSInteger topSpace = (arc4random() % 676) % (int)self.view.frame.size.height + 20;

        UIView *newView = [[UIView alloc] init];
        newView.backgroundColor = color;
        newView.frame = CGRectMake(leftSpace, topSpace, 10, 10);
        [self.view addSubview:newView];

        [_views addObject:newView];
    }
    NSTimeInterval endTime = [NSDate timeIntervalSinceReferenceDate];

    NSTimeInterval timeInterval = endTime - startTime;

    NSMutableDictionary *frameDictionary = _resultDictionary[@"Frame"];
    NSMutableDictionary *currentTimesDictionary = frameDictionary[@(number)] ?: [[NSMutableDictionary alloc] init];
    NSNumber *times = currentTimesDictionary[@"times"] ? : @0;
    NSNumber *avgTime = currentTimesDictionary[@"avgTime"] ? : @0;
    currentTimesDictionary[@"avgTime"] = @((times.integerValue * avgTime.doubleValue + timeInterval) / (double)(times.integerValue + 1));
    currentTimesDictionary[@"times"] = @(times.integerValue + 1);
    [frameDictionary setObject:currentTimesDictionary forKey:@(number)];

    _indicateLabel.text = [NSString stringWithFormat:@"%ld: %f", (long)number, endTime-startTime];
}

- (void)generateNestedViews {
    NSInteger number = _textField.text.integerValue;
    for (UIView *view in _views) {
        [view removeFromSuperview];
    }
    _views = [[NSMutableArray alloc] init];

    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    for (NSInteger i = 0; i < number; i++) {
        UIView *leftView = self.view;
        UIView *topView = self.view;
        if (_views.count != 0) {
            NSInteger left = arc4random() % _views.count;
            NSInteger top = arc4random() % _views.count;
            leftView = _views[left];
            topView = _views[top];
        }

        CGFloat hue = ( arc4random() % 256 / 256.0 );  //  0.0 to 1.0
        CGFloat saturation = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from white
        CGFloat brightness = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from black
        UIColor *color = [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];

        UIView *newView = [[UIView alloc] init];
        newView.backgroundColor = color;
        [self.view addSubview:newView];
        if (_views.count == 0) {
            [self.view addSubview:newView];

            [newView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.left.mas_equalTo(0.5);
                make.top.mas_equalTo(20.5);
                make.bottom.mas_equalTo(-40.5);
                make.right.mas_equalTo(-0.5);
            }];
        } else {
            UIView *aView = _views[i - 1];
            [aView addSubview:newView];

            [newView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.left.mas_equalTo(1);
                make.bottom.right.mas_equalTo(-1);
            }];
        }

        [_views addObject:newView];
    }
    NSTimeInterval endTime = [NSDate timeIntervalSinceReferenceDate];

    NSTimeInterval timeInterval = endTime - startTime;

    NSMutableDictionary *autoLayoutDictionary = _resultDictionary[@"NestedAutoLayout"];
    NSMutableDictionary *currentTimesDictionary = autoLayoutDictionary[@(number)] ?: [[NSMutableDictionary alloc] init];
    NSNumber *times = currentTimesDictionary[@"times"] ? : @0;
    NSNumber *avgTime = currentTimesDictionary[@"avgTime"] ? : @0;
    currentTimesDictionary[@"avgTime"] = @((times.integerValue * avgTime.doubleValue + timeInterval) / (double)(times.integerValue + 1));
    currentTimesDictionary[@"times"] = @(times.integerValue + 1);
    [autoLayoutDictionary setObject:currentTimesDictionary forKey:@(number)];

    _indicateLabel.text = [NSString stringWithFormat:@"%ld: %f", (long)number, endTime-startTime];

}

- (void)printerResult {
    NSLog(@"%@", _resultDictionary);
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end