//
//  PreviewViewController.m
//  ImageProcessing
//
//  Created by Ng Hui Qin on 8/6/14.
//  Copyright (c) 2014 huiqintest. All rights reserved.
//

#import "PreviewViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

@interface PreviewViewController ()

@end

@implementation PreviewViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    UIBarButtonItem *backBar = [[UIBarButtonItem alloc] init];
    [backBar setTitle:@"Retake"];
    self.navigationController.navigationBar.topItem.backBarButtonItem = backBar;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/
- (IBAction)saveTapped:(id)sender {
    NSLog(@"saveTapped");
    [[[ALAssetsLibrary alloc] init] writeImageToSavedPhotosAlbum:[self.imagePreview.image CGImage] orientation:(ALAssetOrientation)[self.imagePreview.image imageOrientation] completionBlock:nil];
}

@end
