import SwiftUI

/// A short confirmation that floats up from the bottom and disappears — the iOS
/// equivalent of an Android toast, which the platform doesn't provide natively.
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var symbol: String = "checkmark"
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?

    /// How long the toast stays up.
    private let duration: Duration = .milliseconds(1900)

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    ToastView(message: message)
                        .padding(.bottom, 90)
                        .transition(
                            .move(edge: .bottom)
                            .combined(with: .opacity)
                        )
                        .task(id: message.id) {
                            try? await Task.sleep(for: duration)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.message = nil
                            }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
    }
}

private struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
                .font(.system(size: 13, weight: .bold))
            Text(message.text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(in: .capsule)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    /// Shows a toast whenever `message` becomes non-nil; it clears itself.
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
