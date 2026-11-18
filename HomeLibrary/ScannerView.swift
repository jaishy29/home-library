import SwiftUI
import VisionKit

/// Live barcode scanner. Calls `onISBN` once with the first valid book barcode it sees.
struct ScannerView: View {
    let onISBN: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if scannerAvailable {
                    ZStack {
                        BarcodeScanner { code in
                            if let isbn = ISBN.normalize(code), ISBN.isBookBarcode(isbn) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onISBN(isbn)
                            }
                        }
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                            .frame(width: 270, height: 140)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .frame(maxHeight: 420)
                    Text("Point the camera at the barcode on the back cover")
                        .font(Theme.display(15, .semibold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder").font(.system(size: 54)).foregroundStyle(Theme.accent)
                        Text("The camera scanner isn't available here")
                            .font(Theme.display(18, .semibold)).foregroundStyle(Theme.ink)
                        Text("Allow camera access in Settings → Home Library, or type the ISBN below.")
                            .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 30)
                }

                HStack {
                    TextField("Or type the ISBN", text: $typed)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1.5))
                    Button("Look up") {
                        if let isbn = ISBN.normalize(typed) { onISBN(isbn) }
                    }
                    .buttonStyle(PinkButtonStyle())
                    .disabled(ISBN.normalize(typed) == nil)
                }
                if !typed.isEmpty && ISBN.clean(typed).count >= 10 && ISBN.normalize(typed) == nil {
                    Text("That ISBN's check digit doesn't match. Re-check the number.")
                        .font(.footnote).foregroundStyle(Theme.loan)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(DotBackground())
            .navigationTitle("Scan a book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let b) = item, let value = b.payloadStringValue, ISBN.isBookBarcode(value) {
                    done = true
                    scanner.stopScanning()
                    DispatchQueue.main.async { self.onCode(value) }
                    return
                }
            }
        }
    }
}

struct PinkButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(16, .semibold))
            .foregroundStyle(filled ? Color.white : Theme.accent)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(filled ? Theme.accent : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? .clear : Theme.line, lineWidth: 1.5))
            .shadow(color: filled ? Theme.accent2 : .clear, radius: 0, y: 3)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
