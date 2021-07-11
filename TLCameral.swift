//
//  TLCameral.swift
//  MainTestProgram
//
//  Created by Biggerlens on 2021/7/7.
//  Copyright © 2021 zjn. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation
import SVProgressHUD


enum TLCameraFocusModel : Int {
    // 先找人脸对焦模式
    case AutoFace
    // 固定点对焦模式
    case Changeless
}

enum RunMode : Int {
    case commonMode
    case photoTakeMode
    case videoRecordMode
    case videoRecordEndMode
}

@objc protocol TLCameraDelegate: NSObjectProtocol {
    func didOutputVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer?)
}

@objc protocol TLCameraDataSource: NSObjectProtocol {
//    @objc func faceCenter<T: TLCameral>(inImage camera: T) -> CGPoint
    @objc func faceCenter(inImage camera: FUCamera) -> CGPoint
}

typealias TLCameraRecordVidepCompleted = (String?) -> Void




class FUCamera: NSObject{
    
    private var runMode: RunMode?
    private var hasStarted = false
    private var videoHDREnabled = false
    
    private var frontCameraInput: AVCaptureDeviceInput?//前置摄像头输入
    private var backCameraInput: AVCaptureDeviceInput?//后置摄像头输入
    var captureFormat = Int(kCVPixelFormatType_32BGRA)//采集格式
    
    var videoCaptureQueue: DispatchQueue?//视频采集的队列
    var audioCaptureQueue: DispatchQueue? //音频采集队列
    var mpCaptureQueue: DispatchQueue? //视频采集的队列

    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoConnection: AVCaptureConnection?
    private var videoInputDevice: AVCaptureDeviceInput?
    private var cameraPosition: AVCaptureDevice.Position?
    private var recordEncoder: TLRecordEncoder? //录制编码
    private var audioMicInput: AVCaptureDeviceInput?
    private var audioOutput: AVCaptureAudioDataOutput?//音频输出
    private var recordVidepCompleted: TLCameraRecordVidepCompleted?
    private var mSessionPreset: AVCaptureSession.Preset?
    private var cameraFocusModel: TLCameraFocusModel?
    
    weak var delegate: TLCameraDelegate?
    weak var dataSource: TLCameraDataSource?
    
    
    private var captureSession: AVCaptureSession?
    
    func isFrontCamera() -> Bool {
        return cameraPosition == AVCaptureDevice.Position.front
    }
    
    fileprivate func _checkIfCameraIsAvailable() -> AVAuthorizationStatus {
        let deviceHasCamera = UIImagePickerController.isCameraDeviceAvailable(UIImagePickerController.CameraDevice.rear) || UIImagePickerController.isCameraDeviceAvailable(UIImagePickerController.CameraDevice.front)
        if deviceHasCamera {
            let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
            let userAgreedToUseIt = authorizationStatus == .authorized
            if userAgreedToUseIt {
                return authorizationStatus
            } else if authorizationStatus == AVAuthorizationStatus.notDetermined {
                return authorizationStatus
            } else {
//                _show(NSLocalizedString("Camera access denied", comment: ""), message: NSLocalizedString("You need to go to settings app and grant acces to the camera device to use it.", comment: ""))
                return authorizationStatus
            }
        } else {
//            _show(NSLocalizedString("Camera unavailable", comment: ""), message: NSLocalizedString("The device does not have a camera.", comment: ""))
            return AVAuthorizationStatus.denied
        }
    }

   
    func setUp() {
        // MARK: 初始化输入设备
//       let videoDevices = AVCaptureDevice.devices(for: .video)
//
//
//       /// 前置摄像头
//       let f = videoDevices.filter({ return $0.position == .front }).first
//
//       /// 后置摄像头
//       let b = videoDevices.filter({ return $0.position == .back }).first
        
        let f = frontCamera()
        let b = backCamera()

        frontCameraInput = try? AVCaptureDeviceInput(device: f!)
       
        backCameraInput = try? AVCaptureDeviceInput(device: b!)
       
       /// 音频设备
       let audioDevice = AVCaptureDevice.default(for: .audio)
       
        audioMicInput = try? AVCaptureDeviceInput.init(device: audioDevice!)

       //MARK: 初始化输出设备
        videoCaptureQueue =  DispatchQueue.global(qos: .default)
        audioCaptureQueue = DispatchQueue(label: "com.faceunity.audioCaptureQueue")
       
        videoOutput = AVCaptureVideoDataOutput()
       
        videoOutput?.setSampleBufferDelegate(self, queue: videoCaptureQueue)
       
       ///保证实时性，放弃延迟祯
        videoOutput?.alwaysDiscardsLateVideoFrames = true
       
       ///设置输出格式为 yuv420
        videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        //, AVVideoWidthKey : 100, AVVideoHeightKey: 100
        videoOutput!.setSampleBufferDelegate(self, queue:videoCaptureQueue)
        audioOutput = AVCaptureAudioDataOutput()
       
        audioOutput?.setSampleBufferDelegate(self, queue: audioCaptureQueue)

       ///设置当前摄像头为前置摄像头
        videoInputDevice = isFrontCamera() ? frontCameraInput : backCameraInput
       
       //MARK: 创建会话
       captureSession = AVCaptureSession()
       
       ///开始配置
       captureSession?.beginConfiguration()

       ///将音视频输入输出设备添加到会话中
       if let videoInputDevice = videoInputDevice, captureSession?.canAddInput(videoInputDevice) == true {
           captureSession?.addInput(videoInputDevice)
       }
       
       if let audioMicInput = audioMicInput, captureSession?.canAddInput(audioMicInput) == true{
           captureSession?.addInput(audioMicInput)
       }
       
       if let videoOutput = videoOutput, captureSession?.canAddOutput(videoOutput) == true{
           captureSession?.addOutput(videoOutput)
//            videoOutConfig()
       }
       
       if let audioOutput = audioOutput, captureSession?.canAddOutput(audioOutput) ==  true{
           captureSession?.addOutput(audioOutput)
           
       }
       
      
       ///设置分辨率
       captureSession?.sessionPreset = .hd1280x720
       
       ///提交配置
        captureSession?.commitConfiguration()
        videoConnection = videoOutput?.connection(with: AVMediaType.video)
        videoConnection?.videoOrientation = AVCaptureVideoOrientation.portrait
        videoConnection?.isVideoMirrored = isFrontCamera()
    }
    
    required init(cameraPosition: AVCaptureDevice.Position = .back, captureFormat: Int = Int(kCVPixelFormatType_32BGRA)) {
        super.init()
        self.cameraPosition = cameraPosition
        self.captureFormat = captureFormat
        setUp()
    }

    override init() {
        super.init()
        cameraPosition = .back
        captureFormat = Int(kCVPixelFormatType_32BGRA)
        videoHDREnabled = true
        setUp()
    }
    
    //用来返回是前置摄像头还是后置摄像头
    func camera(with position: AVCaptureDevice.Position) -> AVCaptureDevice? {
//        if #available(iOS 13, *) {
//
//            var newDevice = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position)
//            if newDevice == nil {
//                newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
//            }
//            return newDevice
//        }else
        if #available(iOS 10.2, *) {

            var newDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position)
            if newDevice == nil {
                newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            }
            return newDevice
        } else {
            //  Converted to Swift 5.4 by Swiftify v5.4.29596 - https://swiftify.com/
            //返回和视频录制相关的所有默认设备
            let devices = AVCaptureDevice.devices(for: .video)
            //遍历这些设备返回跟position相关的设备
            for device in devices {
                if device.position == position {
                    return device
                }
            }
            return nil
        }
    }
    //返回前置摄像头
    func frontCamera() -> AVCaptureDevice? {
        return camera(with: AVCaptureDevice.Position.front)
    }
    //返回后置摄像头
    func backCamera() -> AVCaptureDevice? {
        return camera(with: AVCaptureDevice.Position.back)
    }
    
    
    
    
    func startCapture() {
        cameraFocusModel = .AutoFace
        guard let tcaptureSession = captureSession,tcaptureSession.isRunning == false, hasStarted == false else {
            TLLog("----startCapture")
            return
        }
        hasStarted = true
        //        [self addAudio];
        tcaptureSession.startRunning()
        // 设置曝光中点
        focus(with: AVCaptureDevice.FocusMode.continuousAutoFocus, exposeWith: AVCaptureDevice.ExposureMode.continuousAutoExposure, atDevicePoint: CGPoint(x: 0.5, y: 0.5), monitorSubjectAreaChange: true)
    }
    func stopCapture() {
        hasStarted = false
        //    [self removeAudio];
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
        print("视频采集关闭")
    }
    
    func addAudio() {
        audioOutput?.setSampleBufferDelegate(self, queue: audioCaptureQueue)
        if let tcaptureSession = captureSession, let taudioOutput = audioOutput, tcaptureSession.canAddOutput(taudioOutput) {
            captureSession?.addOutput(taudioOutput)
        }
       
    }

    func removeAudio() {
        guard let taudioOutput = audioOutput else {
            return
        }
        captureSession?.removeOutput(taudioOutput)
    }
    
    //切换前后置摄像头
    func changeCameraInputDeviceisFront(_ isFront: Bool) {
        captureSession?.stopRunning()
        if isFront {
            if let tbackCameraInput = backCameraInput{
                captureSession?.removeInput(tbackCameraInput)
            }
            if let tfrontCameraInput = frontCameraInput,captureSession?.canAddInput(tfrontCameraInput) == true {
                captureSession?.addInput(tfrontCameraInput)

                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: camera)

                NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange(_:)), name: .AVCaptureDeviceSubjectAreaDidChange, object: camera)
                TLLog("前置添加监听----")
            }
           
                cameraPosition = AVCaptureDevice.Position.front
        } else {
            if let frontCameraInput = frontCameraInput {
                captureSession?.removeInput(frontCameraInput)
            }
                
                if let backCameraInput = backCameraInput, captureSession?.canAddInput(backCameraInput) == true {
                    captureSession?.addInput(backCameraInput)
                    NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: camera)
                    NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange(_:)), name: .AVCaptureDeviceSubjectAreaDidChange, object: camera)
                            print("后置添加监听----")
            }
            cameraPosition = AVCaptureDevice.Position.back
        }
        
        let deviceInput = isFront ? frontCameraInput : backCameraInput
        captureSession?.beginConfiguration() // the session to which the receiver's AVCaptureDeviceInput is added.
            do {
                try deviceInput?.device.lockForConfiguration()
            } catch {
                captureSession?.commitConfiguration()
                return
            }
        deviceInput?.device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
        deviceInput?.device.unlockForConfiguration()
        captureSession?.commitConfiguration()
        videoConnection?.videoOrientation = .portrait
        if videoConnection?.isVideoMirroringSupported == true {
            videoConnection?.isVideoMirrored = isFront
        }
        // 与标准视频稳定相比，这种稳定方法减少了摄像机的视野，在视频捕获管道中引入了更多的延迟，并消耗了更多的系统内存
        if videoConnection?.isVideoStabilizationSupported == true && !isFront {
            //前置保持大视野，关闭防抖
            videoConnection?.preferredVideoStabilizationMode = .standard
            TLLog("activeVideoStabilizationMode = \(videoConnection?.activeVideoStabilizationMode.rawValue ?? 0)")
        } else {
            TLLog("connection don't support video stabilization")
            videoConnection?.preferredVideoStabilizationMode = .off
        }

        captureSession?.startRunning()
    }
    
    func currentDeviceInput() -> AVCaptureDeviceInput? {
        let deviceInput = isFrontCamera() ? frontCameraInput : backCameraInput
        return deviceInput
    }
    //闪光灯
    func isFlashSuppoted() -> Bool? {
        let deviceInput = currentDeviceInput()
        if deviceInput?.device.hasFlash == true {
            return deviceInput?.device.isFlashAvailable
        }
        return false
        
    }
    
    func setFlashModel(flashMode :AVCaptureDevice.FlashMode) {
        let deviceInput = currentDeviceInput()
        
        if deviceInput?.device.isFlashModeSupported(flashMode) == true {
            do{//ios10.0之后 不推荐使用这种方式
              //'flashMode' was deprecated in iOS 10.0: Use AVCapturePhotoSettings.flashMode instead.
                try deviceInput?.device.lockForConfiguration()
            }catch{
            }
            deviceInput?.device.flashMode = flashMode
            deviceInput?.device.unlockForConfiguration()
        }
    }
    ///手电筒定义
    func isTorchSuppoted() -> Bool? {
        let deviceInput = currentDeviceInput()
        if deviceInput?.device.hasTorch == true {
            return deviceInput?.device.isTorchAvailable
        }
        return false
    }
    
    func setFlashModel(torchMode :AVCaptureDevice.TorchMode) {
        let deviceInput = currentDeviceInput()
        
        if deviceInput?.device.isTorchModeSupported(torchMode) == true {
            if deviceInput?.device.isTorchActive == true && deviceInput?.device.torchMode == torchMode {
                return
            }
            do {
                try deviceInput?.device.lockForConfiguration()
                deviceInput?.device.torchMode = .on
                try deviceInput?.device.setTorchModeOn(level: 0.5) //值必须在0 - 1.0直接，不然会抛出崩溃
                deviceInput?.device.unlockForConfiguration()
                } catch  {
             }
        }
    }
     

    // 当前分辨率是否支持前后置
    func isSupportsSessionPreset(_ isFront: Bool) -> Bool {
        guard let tmSessionPreset = mSessionPreset else {
            return false
        }
        if isFront == true {
            return frontCameraInput?.device.supportsSessionPreset(tmSessionPreset) == true
        } else {
            return backCameraInput?.device.supportsSessionPreset(tmSessionPreset) == true
        }
    }


    /// 设置采集方向
    /// - Parameter orientation: 方向
    func setCaptureVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        videoConnection?.videoOrientation = orientation
    }
    

    /// 切换回连续对焦和曝光模式
    /// 中心店对焦和曝光(centerPoint)
    /// 恢复以屏幕中心自动连续对焦和曝光
    func resetFocusAndExposureModes() {
        let focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
        let canResetFocus = videoInputDevice?.device.isFocusPointOfInterestSupported == true && videoInputDevice?.device.isFocusModeSupported(focusMode) == true

        let exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
        let canResetExposure = videoInputDevice?.device.isExposurePointOfInterestSupported == true && videoInputDevice?.device.isExposureModeSupported(exposureMode) == true
        let centerPoint = CGPoint(x: 0.5, y: 0.5)

       
        do {
            try videoInputDevice?.device.lockForConfiguration()
        } catch(let error){
            TLLog("\(error)")
            return
        }
        if canResetFocus {
            videoInputDevice?.device.focusMode = focusMode
            videoInputDevice?.device.focusPointOfInterest = centerPoint
        }
        if canResetExposure {
            videoInputDevice?.device.exposureMode = exposureMode
            videoInputDevice?.device.exposurePointOfInterest = centerPoint
        }
        videoInputDevice?.device.unlockForConfiguration()
    }
    
    @objc func subjectAreaDidChange(_ notification: Notification?) {
        videoCaptureQueue?.async(execute: { [self] in
            let devicePoint = CGPoint(x: 0.5, y: 0.5)
            focus(with: AVCaptureDevice.FocusMode.continuousAutoFocus, exposeWith: AVCaptureDevice.ExposureMode.continuousAutoExposure, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)

            cameraChangeModle(.AutoFace)
        })

    }
    
    // MARK: -  曝光补偿
    func setExposureValue(_ value: Float) {
        //    NSLog(@"camera----曝光值----%lf",value);
        
        do {
            try videoInputDevice?.device.lockForConfiguration()
        } catch(let error) {
            TLLog("\(error)")
            return
        }
        videoInputDevice?.device.exposureMode = .continuousAutoExposure
        videoInputDevice?.device.setExposureTargetBias(value, completionHandler: nil)
        videoInputDevice?.device.unlockForConfiguration()
    }
    // MARK: -  分辨率
    func changeSessionPreset(_ sessionPreset: AVCaptureSession.Preset) -> Bool {

        if captureSession?.canSetSessionPreset(sessionPreset) == true {

            if captureSession?.isRunning == true {
                captureSession?.stopRunning()
            }
            captureSession?.sessionPreset = sessionPreset
            mSessionPreset = sessionPreset
            captureSession?.startRunning()

            return true
        }
        return false
    }
    
    // MARK: -  镜像
    func changeVideoMirrored(_ videoMirrored: Bool) {
        if videoConnection?.isVideoMirroringSupported == true {
            videoConnection?.isVideoMirrored = videoMirrored
        }
    }
    // MARK: -  帧率
    func changeVideoFrameRate(_ frameRate: Int) {
        if frameRate <= 30 {
            //此方法可以设置相机帧率,仅支持帧率小于等于30帧.
            let videoDevice = AVCaptureDevice.default(for: .video)
            do {
                try videoDevice?.lockForConfiguration()
                
            } catch {
                return
            }
            videoDevice?.activeVideoMinFrameDuration = CMTimeMake(value: 10, timescale: Int32(frameRate * 10))
            videoDevice?.activeVideoMaxFrameDuration = CMTimeMake(value: 10, timescale: Int32(frameRate * 10))
            videoDevice?.unlockForConfiguration()
            return
        }
        let videoDevice = AVCaptureDevice.default(for: .video)
        guard let tvideoDevice = videoDevice else {
            return
        }
        for vFormat in tvideoDevice.formats {
            let description = vFormat.formatDescription
            let maxRate = Float((vFormat.videoSupportedFrameRateRanges[0]).maxFrameRate)
            if maxRate > Float(frameRate - 1) && CMFormatDescriptionGetMediaSubType(description) == FourCharCode(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                do {
                    try videoDevice?.lockForConfiguration()

                   
                } catch {
                    return
                }
                // 设置分辨率的方法activeFormat与sessionPreset是互斥的
                videoDevice?.activeFormat = vFormat
                videoDevice?.activeVideoMinFrameDuration = CMTimeMake(value: 10, timescale: Int32(frameRate * 10))
                videoDevice?.activeVideoMaxFrameDuration = CMTimeMake(value: 10, timescale: Int32(frameRate * 10))
                videoDevice?.unlockForConfiguration()
                break
            }
        }
    }
    
    func focusPointSupported() -> Bool {
        return videoInputDevice?.device.isFocusPointOfInterestSupported == true
    }

    func exposurePointSupported() -> Bool {
        return videoInputDevice?.device.isExposurePointOfInterestSupported == true
    }

    
    
    // MARK: -  人脸曝光逻辑
    func cameraFocusAndExpose() {
        if cameraFocusModel == .AutoFace {

            if self.dataSource != nil && self.dataSource?.responds(to: #selector(TLCameraDataSource.faceCenter(inImage:))) == true {
                let center = dataSource?.faceCenter(inImage: self)
                if let center = center, center.y >= 0 {
                    focus(with: AVCaptureDevice.FocusMode.continuousAutoFocus, exposeWith: AVCaptureDevice.ExposureMode.continuousAutoExposure, atDevicePoint: center, monitorSubjectAreaChange: true)
                } else {
                    focus(with: AVCaptureDevice.FocusMode.continuousAutoFocus, exposeWith: AVCaptureDevice.ExposureMode.continuousAutoExposure, atDevicePoint: CGPoint(x: 0.5, y: 0.5), monitorSubjectAreaChange: true)
                }
               
            }
       }
        
        
    }
    
    
    func videpCompleted() {
        print("1111")
        
        recordEncoder = nil
        if let recordVidepCompleted = recordVidepCompleted,let path = recordEncoder?.path {
            recordVidepCompleted(path)
        }
    }
    func takePhotoAndSave() {
        runMode = .photoTakeMode
    }

    //开始录像
    func startRecord() {
        runMode = .videoRecordMode
    }

    //停止录像
    func stopRecord(withCompletionHandler handler: @escaping (_ videoPath: String?) -> Void) {
        recordVidepCompleted = handler
        runMode = .videoRecordEndMode

    }
    
    func image(from pixelBufferRef: CVPixelBuffer?) -> UIImage? {

        if let pixelBufferRef = pixelBufferRef {
            CVPixelBufferLockBaseAddress(pixelBufferRef, [])
        }

        let SW = UIScreen.main.bounds.size.width
        let SH = UIScreen.main.bounds.size.height

        var width: CGFloat = 0
        
        if let pixelBufferRef = pixelBufferRef {
            width = CGFloat(CVPixelBufferGetWidth(pixelBufferRef))
        }
        var height: CGFloat = 0
        if let pixelBufferRef = pixelBufferRef {
            height = CGFloat(CVPixelBufferGetHeight(pixelBufferRef))
        }
        
        let dw: CGFloat = width / SW
        let dh = height / SH

        var cropW = width
        var cropH = height
        
        if dw > dh {
               cropW = SW * dh
           } else {
               cropH = SH * dw
           }

        let cropX: CGFloat = (width - cropW) * 0.5
           let cropY: CGFloat = (height - cropH) * 0.5
        
        var ciImage: CIImage? = nil
            if let pixelBufferRef = pixelBufferRef {
                ciImage = CIImage(cvPixelBuffer: pixelBufferRef)
            }

            let temporaryContext = CIContext(options: nil)
        guard let tciImage = ciImage,let videoImage = temporaryContext.createCGImage(
                tciImage,
                from: CGRect(
                    x: cropX,
                    y: cropY,
                    width: cropW,
                    height: cropH)) else {
            return nil
        }
        
        
        let image = UIImage(cgImage: videoImage)
//            CGImageRelease(videoImage)
            if let pixelBufferRef = pixelBufferRef {
                CVPixelBufferUnlockBaseAddress(pixelBufferRef, [])
            }

            return image
        
    }
    
    @objc func image(_ image: UIImage?, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        if error != nil {
            SVProgressHUD.showError(withStatus: TLLocalizedString("保存图片失败"))
        } else {
            SVProgressHUD.showSuccess(withStatus: TLLocalizedString("图片已保存到相册"))
        }
    }
            
   
    /// 查询当前相机最大曝光补偿信息
    /// - Parameters:
    ///   - current: 当前
    ///   - max: 最大
    ///   - min: 最小
    
    func getCurrentExposureValue(_ current: UnsafeMutablePointer<Float>?, max: UnsafeMutablePointer<Float>?, min: UnsafeMutablePointer<Float>?) {
//        AVCaptureDevice
        guard let tcamera = videoInputDevice?.device else {
            return
        }
        min?.pointee = tcamera.minExposureTargetBias
            //UnsafeMutablePointer<Float>(mutating: camera?.minExposureTargetBias)
        max?.pointee = tcamera.maxExposureTargetBias
//            UnsafeMutablePointer<Float>(mutating: camera?.maxExposureTargetBias)
        current?.pointee = tcamera.exposureTargetBias
//            UnsafeMutablePointer<Float>(mutating: camera?.exposureTargetBias)

    }
    
    func getCurrentExposureValueInOut( current: inout Float?, max: inout Float?, min: inout Float?) {

        min = videoInputDevice?.device.minExposureTargetBias
            
        max = videoInputDevice?.device.maxExposureTargetBias
//
        current = videoInputDevice?.device.exposureTargetBias
//

    }
            
    /// 设置曝光模式和兴趣点
    /// @param focusMode 对焦模式
    /// @param exposureMode 曝光模式
    /// @param point 兴趣点
    /// @param monitorSubjectAreaChange   是否监听主题变化
    func focus(with focusMode: AVCaptureDevice.FocusMode, exposeWith exposureMode: AVCaptureDevice.ExposureMode, atDevicePoint point: CGPoint, monitorSubjectAreaChange: Bool) {
        
        videoCaptureQueue?.async(execute: { [self] in
            let device = videoInputDevice?.device

            do {
                try device?.lockForConfiguration()
            } catch {
                return
            }
            if device?.isFocusPointOfInterestSupported == true && device?.isFocusModeSupported(focusMode) == true  {
                device?.focusPointOfInterest = point
                device?.focusMode = focusMode
            }
            if device?.isExposurePointOfInterestSupported == true && device?.isExposureModeSupported(exposureMode) == true {
                device?.exposurePointOfInterest = point
                device?.exposureMode = exposureMode
            }
            //            NSLog(@"---point --%@",NSStringFromCGPoint(point));
            device?.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
            device?.unlockForConfiguration()
        })
        
    }

    ///  修改对焦模式
    /// @param modle 对焦模式
//        func cameraChangeModle(_ modle: FUCameraFocusModel) {
//        }
    
    //缩放
    func maxZoomFactor() -> CGFloat {
        return CGFloat(min(videoInputDevice?.device.activeFormat.videoMaxZoomFactor ?? 1, 4.0))
    }
    //  缩放
    //  可用于模拟对焦
    func setZoomValue(_ zoomValue: CGFloat) {
        let camera = videoInputDevice?.device
        if camera?.isRampingVideoZoom == true {
            
            do {
                try camera?.lockForConfiguration()
            } catch {
                return
            }
            let zoomFactor = pow(maxZoomFactor(), zoomValue)
            camera?.videoZoomFactor = zoomFactor
            camera?.unlockForConfiguration()
        }

    }
    
    func cameraChangeModle(_ modle: TLCameraFocusModel) {
        cameraFocusModel = modle
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)

        print("camera dealloc")
    }
    
}




//MARK:--
extension FUCamera: AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if captureOutput == audioOutput {

            if runMode == .videoRecordMode {

                if recordEncoder == nil {
                    return
                }
//                CFRetain(sampleBuffer)
                // 进行数据编码
                recordEncoder?.encodeFrame(sampleBuffer, isVideo: false)
            }
            return
        }
        if self.delegate != nil && self.delegate?.responds(to: #selector(TLCameraDelegate.didOutputVideoSampleBuffer(_ :))) == true {
                delegate?.didOutputVideoSampleBuffer(sampleBuffer)
            }
            // 人脸对焦判断
            cameraFocusAndExpose()
        switch runMode {
        case .commonMode:
            break
        case .photoTakeMode:
            runMode = .commonMode
                let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                let image = self.image(from: buffer)
                if let image = image {
                    UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
                }
            break
        case .videoRecordMode:
                if recordEncoder == nil {
                    let currentDate = Date() //获取当前时间，日期
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "YYYYMMddhhmmssSS"
                    let dateString = dateFormatter.string(from: currentDate)
                    let videoPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(dateString).mp4").path
                    let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                   var frameWidth: Float? = nil
                   if let buffer = buffer {
                       frameWidth = Float(CVPixelBufferGetWidth(buffer))
                   }
                   var frameHeight: Float? = nil
                    if let frameWidth = frameWidth, let frameHeight = frameHeight, frameWidth != 0 && frameHeight != 0 {

                        recordEncoder = TLRecordEncoder.encoder(forPath: videoPath, height: Int(frameHeight), width: Int(frameWidth), channels: 1, samples: 44100)
                        
                                    return
                                }
                            }
//            CFRetain(sampleBuffer)
            // 进行数据编码
            recordEncoder?.encodeFrame(sampleBuffer, isVideo: true)
        case .videoRecordEndMode:
            runMode = .commonMode

                //            if (self.recordEncoder.writer.status == AVAssetWriterStatusUnknown) {
                //                self.recordEncoder = nil;
                //            }else{
            
            recordEncoder?.finish(withCompletionHandler: { [weak self] in
                self?.videpCompleted()
            })
            default:
                break
        }
    }
    
}

