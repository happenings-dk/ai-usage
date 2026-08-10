import SwiftUI
import VisionKit

/// Full-screen native scanner for AI Usage pairing QR codes.
struct PairingScannerView: View {
    let onCode: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PairingDataScanner { url in
                onCode(url)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Scan Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PairingDataScanner: UIViewControllerRepresentable {
    let onCode: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (URL) -> Void
        private var didFindCode = false

        init(onCode: @escaping (URL) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didFindCode else {
                return
            }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let value = barcode.payloadStringValue,
                      let url = URL(string: value),
                      url.scheme == "aiusage" else {
                    continue
                }
                didFindCode = true
                onCode(url)
                return
            }
        }
    }
}
