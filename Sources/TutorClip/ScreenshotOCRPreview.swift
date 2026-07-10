import SwiftUI

struct ScreenshotOCRPreview: View {
    let image: NSImage

    var body: some View {
        GeometryReader { proxy in
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
