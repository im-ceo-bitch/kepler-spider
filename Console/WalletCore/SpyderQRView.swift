import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// QR encodes an actual public address, not a placeholder image.
struct SpyderQRView: View {
    let address: String
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    var body: some View {
        Group {
            if let image = makeImage() {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(17)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("QR-код публичного адреса кошелька")
            } else {
                Label("Не удалось создать QR-код", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(WalletTheme.secondary)
            }
        }
    }

    private func makeImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(address.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
