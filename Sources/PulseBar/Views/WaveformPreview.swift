import SwiftUI

struct WaveformPreview: View {
    let shape: WaveformShape

    var body: some View {
        GeometryReader { proxy in
            Image(
                nsImage: WaveformRenderer.stylePreviewImage(
                    size: proxy.size,
                    shape: shape
                )
            )
            .resizable()
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityLabel("波形样式预览")
    }
}
