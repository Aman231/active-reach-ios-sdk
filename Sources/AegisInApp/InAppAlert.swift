import SwiftUI

struct InAppAlert: View {
    
    let campaign: AegisInAppManager.InAppCampaign
    let onDismiss: () -> Void
    let onAction: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3 * opacity)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismiss()
                }
            
            VStack(spacing: 20) {
                if let imageUrl = campaign.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        case .failure(_):
                            EmptyView()
                        case .empty:
                            ProgressView()
                                .frame(width: 80, height: 80)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                
                Text(campaign.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                
                Text(campaign.body)
                    .font(.subheadline)
                    .foregroundColor(textColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Divider()
                    .padding(.horizontal, -20)
                
                HStack(spacing: 0) {
                    if campaign.buttonText != nil {
                        Button(action: dismiss) {
                            Text("Cancel")
                                .font(.body)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        
                        Divider()
                            .frame(height: 44)
                    }
                    
                    Button(action: handleAction) {
                        Text(campaign.buttonText ?? "OK")
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, -20)
                .padding(.bottom, -20)
            }
            .padding(20)
            .frame(width: 280)
            .background(backgroundColor)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
    
    private var backgroundColor: Color {
        if let hex = campaign.backgroundColor {
            return Color(hex: hex) ?? Color(UIColor.systemBackground)
        }
        return Color(UIColor.systemBackground)
    }
    
    private var textColor: Color {
        if let hex = campaign.textColor {
            return Color(hex: hex) ?? Color(UIColor.label)
        }
        return Color(UIColor.label)
    }
    
    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 0.8
            opacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func handleAction() {
        onAction()
        
        if let actionUrl = campaign.actionUrl, let url = URL(string: actionUrl) {
            UIApplication.shared.open(url)
        }
        
        dismiss()
    }
}
