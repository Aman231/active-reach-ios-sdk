import SwiftUI

struct InAppFullScreen: View {
    
    let campaign: AegisInAppManager.InAppCampaign
    let onDismiss: () -> Void
    let onAction: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            backgroundColor
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(textColor.opacity(0.7))
                            .padding()
                    }
                }
                
                Spacer()
                
                VStack(spacing: 24) {
                    if let imageUrl = campaign.imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 300, maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            case .failure(_):
                                EmptyView()
                            case .empty:
                                ProgressView()
                                    .frame(width: 200, height: 200)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    Text(campaign.title)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Text(campaign.body)
                        .font(.system(size: 18))
                        .foregroundColor(textColor.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let buttonText = campaign.buttonText {
                        Button(action: handleAction) {
                            Text(buttonText)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: 280)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        .padding(.top, 16)
                    }
                }
                
                Spacer()
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
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
