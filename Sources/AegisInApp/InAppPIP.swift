import SwiftUI
import AVKit

struct InAppPIP: View {
    
    let campaign: AegisInAppManager.InAppCampaign
    let onDismiss: () -> Void
    let onAction: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @State private var offset: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 100, y: UIScreen.main.bounds.height - 200)
    @State private var isExpanded = false
    @State private var player: AVPlayer?
    
    private let pipSize: CGSize = CGSize(width: 120, height: 160)
    private let expandedSize: CGSize = CGSize(width: UIScreen.main.bounds.width - 32, height: 240)
    
    var body: some View {
        ZStack {
            Color.clear.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                if let videoUrl = campaign.videoUrl, let url = URL(string: videoUrl) {
                    ZStack(alignment: .topTrailing) {
                        VideoPlayer(player: player)
                            .frame(
                                width: isExpanded ? expandedSize.width : pipSize.width,
                                height: isExpanded ? expandedSize.height : pipSize.height
                            )
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            .onTapGesture {
                                isExpanded.toggle()
                            }
                        
                        Button(action: dismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(8)
                    }
                    .position(x: offset.x, y: offset.y)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = value.location
                            }
                            .onEnded { value in
                                snapToEdge()
                            }
                    )
                } else if let imageUrl = campaign.imageUrl, let url = URL(string: imageUrl) {
                    ZStack(alignment: .topTrailing) {
                        VStack(spacing: 8) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(
                                            width: isExpanded ? expandedSize.width : pipSize.width,
                                            height: isExpanded ? (expandedSize.height - 60) : (pipSize.height - 40)
                                        )
                                        .clipped()
                                case .failure(_):
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                case .empty:
                                    ProgressView()
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            
                            if isExpanded {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(campaign.title)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    if let buttonText = campaign.buttonText {
                                        Button(action: handleAction) {
                                            Text(buttonText)
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue)
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                            }
                        }
                        .background(backgroundColor)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .onTapGesture {
                            isExpanded.toggle()
                        }
                        
                        Button(action: dismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(6)
                    }
                    .frame(
                        width: isExpanded ? expandedSize.width : pipSize.width,
                        height: isExpanded ? expandedSize.height : pipSize.height
                    )
                    .position(x: offset.x, y: offset.y)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isExpanded {
                                    offset = value.location
                                }
                            }
                            .onEnded { value in
                                if !isExpanded {
                                    snapToEdge()
                                }
                            }
                    )
                }
            }
        }
        .onAppear {
            if let videoUrl = campaign.videoUrl, let url = URL(string: videoUrl) {
                player = AVPlayer(url: url)
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private var backgroundColor: Color {
        if let hex = campaign.backgroundColor {
            return Color(hex: hex) ?? Color.black
        }
        return Color.black
    }
    
    private func snapToEdge() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        let margin: CGFloat = 16
        let halfWidth = pipSize.width / 2
        let halfHeight = pipSize.height / 2
        
        var newX = offset.x
        var newY = offset.y
        
        if offset.x < screenWidth / 2 {
            newX = halfWidth + margin
        } else {
            newX = screenWidth - halfWidth - margin
        }
        
        newY = max(halfHeight + margin + 50, min(offset.y, screenHeight - halfHeight - margin - 50))
        
        withAnimation(.spring()) {
            offset = CGPoint(x: newX, y: newY)
        }
    }
    
    private func dismiss() {
        player?.pause()
        onDismiss()
        presentationMode.wrappedValue.dismiss()
    }
    
    private func handleAction() {
        onAction()
        
        if let actionUrl = campaign.actionUrl, let url = URL(string: actionUrl) {
            UIApplication.shared.open(url)
        }
        
        if !isExpanded {
            dismiss()
        }
    }
}
