import SwiftUI
import UIKit
import PhotosUI
import CoreImage
import ImageIO
import AVFoundation
#if canImport(VisionKit) && os(iOS) && !targetEnvironment(macCatalyst)
import VisionKit
#endif

// Only compact signed invoice tokens. Never treat QR contents as a URL,
// authentication token, account identity or instruction to submit a payment.
enum SpyderPayQRInput {
    static func token(_ raw:String) -> String? {
        let value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard value.utf8.count<=2048,value.range(of:"^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$",options:.regularExpression) != nil else {return nil}
        return value
    }
    static func fromPhoto(_ data:Data) -> String? {
        guard data.count<=15_000_000,let source=CGImageSourceCreateWithData(data as CFData,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2200,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary),
              let detector=CIDetector(ofType:CIDetectorTypeQRCode,context:nil,options:[CIDetectorAccuracy:CIDetectorAccuracyHigh]) else {return nil}
        let tokens=Set(detector.features(in:CIImage(cgImage:image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.compactMap {token($0)})
        return tokens.count==1 ? tokens.first:nil
    }
}

#if canImport(VisionKit) && os(iOS) && !targetEnvironment(macCatalyst)
struct SpyderPayCameraScanner: UIViewControllerRepresentable {
    let onToken:(String)->Void
    let onFailure:()->Void
    static var supported:Bool {DataScannerViewController.isSupported}
    func makeCoordinator()->Coordinator {Coordinator(parent:self)}
    func makeUIViewController(context:Context)->DataScannerViewController {
        let controller=DataScannerViewController(recognizedDataTypes:[.barcode(symbologies:[.qr])],qualityLevel:.balanced,recognizesMultipleItems:true,isHighFrameRateTrackingEnabled:false,isPinchToZoomEnabled:true,isGuidanceEnabled:true,isHighlightingEnabled:true)
        controller.delegate=context.coordinator
        Task { @MainActor in
            do {try controller.startScanning()} catch {context.coordinator.fail()}
        }
        return controller
    }
    func updateUIViewController(_ uiViewController:DataScannerViewController,context:Context) {context.coordinator.parent=self}
    static func dismantleUIViewController(_ uiViewController:DataScannerViewController,coordinator:Coordinator) {coordinator.finished=true;uiViewController.stopScanning()}
    final class Coordinator:NSObject,DataScannerViewControllerDelegate {
        var parent:SpyderPayCameraScanner
        var finished=false
        init(parent:SpyderPayCameraScanner){self.parent=parent}
        func fail(){guard !finished else {return};finished=true;parent.onFailure()}
        func dataScanner(_ dataScanner:DataScannerViewController,didTapOn item:RecognizedItem){
            guard !finished,case .barcode(let barcode)=item,let raw=barcode.payloadStringValue,let token=SpyderPayQRInput.token(raw) else {return}
            finished=true;dataScanner.stopScanning();parent.onToken(token)
        }
        func dataScanner(_ dataScanner:DataScannerViewController,didAdd addedItems:[RecognizedItem],allItems:[RecognizedItem]){
            let values=Set(allItems.compactMap { item -> String? in
                guard case .barcode(let barcode)=item,let raw=barcode.payloadStringValue else {return nil}
                return SpyderPayQRInput.token(raw)
            })
            guard !finished,values.count==1,let token=values.first else {return}
            finished=true;dataScanner.stopScanning();parent.onToken(token)
        }
        func dataScanner(_ dataScanner:DataScannerViewController,becameUnavailableWithError error:DataScannerViewController.ScanningUnavailable){fail()}
    }
}
#endif
