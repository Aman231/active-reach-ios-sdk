import SwiftUI

struct InAppHalfInterstitial: View {
    
    let campaign: AegisInAppManager.InAppCampaign
    let onDismiss: () -> Void
    let onAction: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var offset: CGFloat = UIScreen.main.bounds.height
    @State private var backgroundOpacity: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5 * backgroundOpacity)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    dismiss()
                }
            
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    if let imageUrl = campaign.imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 180)
                                    .clipped()
                            case .failure(_):
                                EmptyView()
                            case .empty:
                                ProgressView()
                                    .frame(height: 180)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    VStack(alignment: .center, spacing: 20) {
                        HStack {
                            Spacer()
                            
                            Button(action: dismiss) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Text(campaign.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(textColor)
                            .multilineTextAlignment(.center)
                        
                        Text(campaign.body)
                            .font(.body)
                            .foregroundColor(textColor.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if let buttonText = campaign.buttonText {
                            Button(action: handleAction) {
                                Text(buttonText)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(24)
                }
                .background(backgroundColor)
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: -10)
                .offset(y: offset)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                offset = 0
                backgroundOpacity = 1.0
            }
        }
    }
    
    private var backgroundColor: Color {
        if let hex = campaign.backgroundColor {
            return Color(hex: hex) ?? .white
        }
        return .white
    }
    
    private var textColor: Color {
        if let hex = campaign.textColor {
            return Color(hex: hex) ?? .black
        }
        return .black
    }
    
    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = UIScreen.main.bounds.height
            backgroundOpacity = 0
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

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
