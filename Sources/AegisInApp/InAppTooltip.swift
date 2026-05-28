import SwiftUI

/// Tooltip-style in-app message.
/// On mobile, renders as a compact card anchored to the bottom of the screen
/// with an arrow indicator, dismissible on tap outside.
struct InAppTooltipView: View {

    let campaign: AegisInAppManager.InAppCampaign
    let onDismiss: () -> Void
    let onAction: () -> Void

    @Environment(\.presentationMode) var presentationMode
    @State private var scale: CGFloat = 0.9
    @State private var opacity: Double = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Transparent tap catcher for dismiss
            Color.clear
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Arrow pointing down
                Triangle()
                    .fill(backgroundColor)
                    .frame(width: 14, height: 8)
                    .rotationEffect(.degrees(180))

                // Tooltip card
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !campaign.title.isEmpty {
                            Text(campaign.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(textColor)
                                .lineLimit(1)
                        }

                        Text(campaign.body)
                            .font(.system(size: 12))
                            .foregroundColor(textColor.opacity(0.9))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        if let btnText = campaign.buttonText {
                            Button(action: handleAction) {
                                Text(btnText)
                                    .font(.system(size: 12, weight: .semibold))
                                    .underline()
                                    .foregroundColor(textColor)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Close X
                    Button(action: dismiss) {
                        Text("\u{00D7}")
                            .font(.system(size: 18))
                            .foregroundColor(textColor.opacity(0.5))
                    }
                }
                .padding(14)
                .background(backgroundColor)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                scale = 1
                opacity = 1
            }
        }
    }

    private var backgroundColor: Color {
        Color(hex: campaign.backgroundColor ?? "#1a1a1a") ?? .black
    }

    private var textColor: Color {
        Color(hex: campaign.textColor ?? "#ffffff") ?? .white
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            scale = 0.9
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDismiss()
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func handleAction() {
        onAction()
        if let urlStr = campaign.actionUrl, let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
        dismiss()
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
