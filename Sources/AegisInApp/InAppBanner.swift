import SwiftUI

struct InAppBanner: View {
    
    let campaign: AegisInAppManager.InAppCampaign
    let onDismiss: () -> Void
    let onAction: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var offset: CGFloat = -200
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                if let imageUrl = campaign.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure(_):
                            EmptyView()
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(campaign.title)
                        .font(.headline)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    
                    Text(campaign.body)
                        .font(.subheadline)
                        .foregroundColor(textColor.opacity(0.8))
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .foregroundColor(textColor.opacity(0.6))
                        .padding(8)
                }
            }
            .padding(16)
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .offset(y: offset)
            .onTapGesture {
                handleAction()
            }
            
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offset = 60
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                dismiss()
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
            offset = -200
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
