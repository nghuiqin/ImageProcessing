//
//  CameraViewController.m
//  ImageProcessing
//  Refer to AVCam sample code provided by Apple.
//  Created by Ng Hui Qin on 7/24/14.
//  Copyright (c) 2014 huiqintest. All rights reserved.
//

#import "CameraViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "AVCamPreviewView.h"
#import "PreviewViewController.h"

static void * SessionRunningAndDeviceAuthorizedContext = &SessionRunningAndDeviceAuthorizedContext;
static void * CapturingStillImageContext = &CapturingStillImageContext;

@interface CameraViewController () <AVCaptureFileOutputRecordingDelegate>

// For use in storyboards
@property (weak, nonatomic) IBOutlet AVCamPreviewView *cameraView;
@property (weak, nonatomic) IBOutlet UIButton *takePhoto;
- (IBAction)snapTapped:(id)sender;

// Session management
@property (nonatomic) dispatch_queue_t sessionQueue; //communicate
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic) AVCaptureStillImageOutput *photoOutput;

// Utilities
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;
@property (nonatomic) BOOL lockInterfaceRotation;
@property (nonatomic) id runtimeErrorHandlingObserver;

// Passing variable
@property (nonatomic, strong) PreviewViewController *previewVC;
@end


@implementation CameraViewController

- (BOOL)isSessionRunningAndDeviceAuthorized
{
    return [[self session] isRunning] && [self isDeviceAuthorized];
}

+ (NSSet *)keyPathsForValuesAffectingDeviceAuthorized
{
    return [NSSet setWithObjects:@"session.running",@"deviceAuthorized", nil];
}

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
    // Create the AVCaptureSession
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [self setSession:session];
    
    // Setup the camera view
    [[self cameraView] setSession:session];
    
    // Check for the device authorization
    [self checkDeviceAuthorizationStatus];
    
    // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
	// Why not do all of this on the main queue?
	// -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue so that the main queue isn't blocked (which keeps the UI responsive).
    dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
	[self setSessionQueue:sessionQueue];
    
    dispatch_async(sessionQueue, ^{
        [self setBackgroundRecordingID:UIBackgroundTaskInvalid];
        
        NSError *error = nil;
        
        AVCaptureDevice *videoDevice = [CameraViewController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        
        if (error)
        {
            NSLog(@"%@", error);
        }
        
        if ([session canAddInput:videoDeviceInput])
        {
            [session addInput:videoDeviceInput];
            [self setVideoDeviceInput:videoDeviceInput];
            
            dispatch_async(dispatch_get_main_queue(), ^{
				// Why are we dispatching this to the main queue?
				// Because AVCaptureVideoPreviewLayer is the backing layer for AVCamPreviewView and UIView can only be manipulated on main thread.
				// Note: As an exception to the above rule, it is not necessary to serialize video orientation changes on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                
				[[(AVCaptureVideoPreviewLayer *)[[self cameraView] layer] connection] setVideoOrientation:(AVCaptureVideoOrientation)[self interfaceOrientation]];
			});
        }
        
        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if([session canAddOutput:stillImageOutput])
        {
            [stillImageOutput setOutputSettings:@{AVVideoCodecKey:AVVideoCodecJPEG}];
            [session addOutput:stillImageOutput];
            [self setPhotoOutput:stillImageOutput];
        }
    });
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated
{
    dispatch_async([self sessionQueue], ^{
        [self addObserver:self forKeyPath:@"sessionRunningAndDeviceAuthorized" options:(NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew)  context:SessionRunningAndDeviceAuthorizedContext];
        [self addObserver:self forKeyPath:@"photoOutput.capturingStillImage" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:CapturingStillImageContext];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:[[self videoDeviceInput] device]];
        
        __weak CameraViewController *weakSelf = self;
        [self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:[self session] queue:nil usingBlock:^(NSNotification *note) {
            CameraViewController *strongSelf = weakSelf;
            dispatch_async([strongSelf sessionQueue],^{
                // Manually restart the session
                [[strongSelf session] startRunning];
            });
        }]];
        [[self session] startRunning];
    });
}

- (void)viewDidDisappear:(BOOL)animated{
    
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    NSLog(@"captureOutput: didFinishRecordingToOutputFileAtURL");
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
    NSLog(@"captureOutput: didStartRecordingToOutputFileAtURL");
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == CapturingStillImageContext)
    {
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        
        if (isCapturingStillImage)
        {
            [self runStillImageCaptureAnimation];
        }
    }
    else if (context == SessionRunningAndDeviceAuthorizedContext)
    {
        BOOL isRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        if (isRunning)
        {
            //Set button available
        }
        else
        {
            //Disable button
        }
    }
    else
    {
        [self observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async([self sessionQueue], ^{
        AVCaptureDevice *device = [[self videoDeviceInput] device];
        NSError *error = nil;
        if ([device lockForConfiguration:&error])
        {
            if([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode])
            {
                [device setFocusMode:focusMode];
                [device setFocusPointOfInterest:point];
            }
            if([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode])
            {
                [device setExposureMode:exposureMode];
                [device setExposurePointOfInterest:point];
            }
            [device setSubjectAreaChangeMonitoringEnabled:YES];
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"%@",error);
        }
    });
}

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = [devices firstObject];
    
    for (AVCaptureDevice *device in devices)
    {
        if ([device position] == position)
        {
            captureDevice = device;
            break;
        }
    }
    return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
    if([device hasFlash] && [device isFlashModeSupported:flashMode])
    {
         NSError *error = nil;
        if([device lockForConfiguration:&error])
        {
            [device setFlashMode:flashMode];
            [device unlockForConfiguration];
        }
        else
        {
            NSLog(@"%@",error);
        }
    }
}

#pragma mark UI
- (void)runStillImageCaptureAnimation
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[[self cameraView] layer] setOpacity:0.0];
		[UIView animateWithDuration:.25 animations:^{
			[[[self cameraView] layer] setOpacity:1.0];
		}];
	});
}

- (void)checkDeviceAuthorizationStatus
{
    NSString *mediaType = AVMediaTypeVideo;
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
        if (granted)
        {
            //Granted access to mediaType
            [self setDeviceAuthorized:YES];
        }
        else
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[[UIAlertView alloc] initWithTitle:@"Camera!" message:@"Doesn't have permission to camera, please change the privacy setting!" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
                [self setDeviceAuthorized:NO];
            });
        }
    }];
}

#pragma mark Action

- (IBAction)snapTapped:(id)sender {
    dispatch_async([self sessionQueue], ^{
		// Update the orientation on the still image output video connection before capturing.
		[[[self photoOutput] connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:[[(AVCaptureVideoPreviewLayer *)[[self cameraView] layer] connection] videoOrientation]];
		
		// Flash set to Auto for Still Capture
		[CameraViewController setFlashMode:AVCaptureFlashModeAuto forDevice:[[self videoDeviceInput] device]];
		
		// Capture a still image.
		[[self photoOutput] captureStillImageAsynchronouslyFromConnection:[[self photoOutput] connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
			
			if (imageDataSampleBuffer)
			{
				NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
				UIImage *image = [[UIImage alloc] initWithData:imageData];
                
				[_previewVC.imagePreview setImage:[self cropImageInSquare:image]];
			}
		}];
	});
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
	CGPoint devicePoint = CGPointMake(.5, .5);
	[self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (UIImage *)cropImageInSquare:(UIImage *)originalImage
{
    //calculate scale factor to go between cropframe and original image
    float SF = originalImage.size.width / 320;
    
    //find the centre x,y coordinates of image
    float centreX = originalImage.size.width / 2;
    float centreY = originalImage.size.height / 2;
    
    //calculate crop parameters
    float cropX = centreX - ((320 / 2) * SF);
    float cropY = centreY - ((320 / 2) * SF);

    CGRect cropRect = CGRectMake(cropX, cropY, 320*SF, 320*SF);
    
    CGAffineTransform rectTransform;
    switch (originalImage.imageOrientation)
    {
        case UIImageOrientationLeft:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(M_PI_2), 0, -originalImage.size.height);
            break;
        case UIImageOrientationRight:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(-M_PI_2), -originalImage.size.width, 0);
            break;
        case UIImageOrientationDown:
            rectTransform = CGAffineTransformTranslate(CGAffineTransformMakeRotation(-M_PI), -originalImage.size.width, -originalImage.size.height);
            break;
        default:
            rectTransform = CGAffineTransformIdentity;
    };
    rectTransform = CGAffineTransformScale(rectTransform, originalImage.scale, originalImage.scale);
    
    CGImageRef imageRef = CGImageCreateWithImageInRect([originalImage CGImage], CGRectApplyAffineTransform(cropRect, rectTransform));
    UIImage *result = [UIImage imageWithCGImage:imageRef scale:originalImage.scale orientation:originalImage.imageOrientation];
    CGImageRelease(imageRef);
    //return result;
    //Now want to scale down cropped image!
    //want to multiply frames by 2 to get retina resolution
    CGRect scaledImgRect = CGRectMake(0, 0, (320 * 2), (320 * 2));
    
    UIGraphicsBeginImageContextWithOptions(scaledImgRect.size, NO, [UIScreen mainScreen].scale);
    
    [result drawInRect:scaledImgRect];
    
    UIImage *scaledNewImage = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return scaledNewImage;

}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Make sure your segue name in storyboard is the same as this line
    if ([[segue identifier] isEqualToString:@"previewPhoto"])
    {
        // Pass any objects to the view controller here, like...
        _previewVC = segue.destinationViewController;
    }
}

@end
