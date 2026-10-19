import InsightCore
import InsightPresentation
import SwiftUI

struct NoticeCard<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }
}

extension NoticeCard where Actions == EmptyView {
    init(icon: String, tint: Color, title: String, message: String) {
        self.init(icon: icon, tint: tint, title: title, message: message) { EmptyView() }
    }
}
