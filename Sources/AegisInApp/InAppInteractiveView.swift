import SwiftUI

/// Unified interactive renderer for all 8 interactive in-app message sub-types (iOS).
/// Follows the existing SwiftUI View + UIHostingController pattern.
struct InAppInteractiveView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let subType: String
    let responseService: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void

    var body: some View {
        switch subType {
        case "nps_survey":     NpsSurveyView(campaign: campaign, service: responseService, onDismiss: onDismiss, onAction: onAction)
        case "star_rating":    StarRatingView(campaign: campaign, service: responseService, onDismiss: onDismiss, onAction: onAction)
        case "quick_poll":     QuickPollView(campaign: campaign, service: responseService, onDismiss: onDismiss, onAction: onAction)
        case "quiz":           QuizView(campaign: campaign, service: responseService, onDismiss: onDismiss, onAction: onAction)
        case "countdown_offer": CountdownOfferView(campaign: campaign, onDismiss: onDismiss, onAction: onAction)
        case "multi_step_form": MultiStepFormView(campaign: campaign, service: responseService, onDismiss: onDismiss, onAction: onAction)
        case "spin_wheel":     SpinWheelView(campaign: campaign, service: responseService, onDismiss: onDismiss, onAction: onAction)
        case "scratch_card":   ScratchCardView(campaign: campaign, service: responseService, onDismiss: onDismiss, onAction: onAction)
        default:               EmptyView()
        }
    }
}

// MARK: - Helpers

private func bg(_ campaign: AegisInAppManager.InAppCampaign) -> Color {
    Color(hex: campaign.backgroundColor ?? "#4169e1") ?? .blue
}
private func fg(_ campaign: AegisInAppManager.InAppCampaign) -> Color {
    Color(hex: campaign.textColor ?? "#ffffff") ?? .white
}
private func icStr(_ campaign: AegisInAppManager.InAppCampaign, _ key: String) -> String? {
    campaign.interactiveConfig?[key]?.value as? String
}
private func icInt(_ campaign: AegisInAppManager.InAppCampaign, _ key: String) -> Int? {
    campaign.interactiveConfig?[key]?.value as? Int
}
private func icBool(_ campaign: AegisInAppManager.InAppCampaign, _ key: String) -> Bool {
    campaign.interactiveConfig?[key]?.value as? Bool ?? false
}
private func icArr(_ campaign: AegisInAppManager.InAppCampaign, _ key: String) -> [Any]? {
    campaign.interactiveConfig?[key]?.value as? [Any]
}

// MARK: - Shell

private struct OverlayShell<Content: View>: View {
    let bgColor: Color
    let onDismiss: () -> Void
    let maxWidth: CGFloat
    @ViewBuilder let content: Content

    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.6 * opacity).edgesIgnoringSafeArea(.all).onTapGesture { dismiss() }
            VStack(spacing: 0) { content }
                .padding(24)
                .frame(maxWidth: maxWidth)
                .background(bgColor)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                .scaleEffect(scale)
                .opacity(opacity)
                .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { scale = 1; opacity = 1 }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { scale = 0.8; opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}

// MARK: - 1. NPS Survey

private struct NpsSurveyView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let service: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void
    @State private var submitted = false

    var body: some View {
        let question = icStr(campaign, "nps_question") ?? "How likely are you to recommend us?"
        OverlayShell(bgColor: bg(campaign), onDismiss: onDismiss, maxWidth: 360) {
            Text(question).font(.system(size: 16, weight: .bold)).foregroundColor(fg(campaign)).multilineTextAlignment(.center)
            Spacer().frame(height: 16)

            if !submitted {
                HStack(spacing: 4) {
                    ForEach(0..<11, id: \.self) { i in
                        Button(action: {
                            submitted = true
                            service.submitResponse(campaignId: campaign.id, responseType: "nps",
                                payload: ["score": i], variantId: campaign.assignedVariantId) { _ in onAction() }
                        }) {
                            Text("\(i)").font(.system(size: 12, weight: .semibold)).foregroundColor(fg(campaign))
                                .frame(width: 28, height: 28)
                                .background(fg(campaign).opacity(0.15)).cornerRadius(6)
                        }
                    }
                }
                HStack {
                    Text("Not likely").font(.system(size: 11)).foregroundColor(fg(campaign).opacity(0.6))
                    Spacer()
                    Text("Very likely").font(.system(size: 11)).foregroundColor(fg(campaign).opacity(0.6))
                }
            } else {
                Text("Thank you for your feedback!").font(.system(size: 14)).foregroundColor(fg(campaign))
            }

            Spacer().frame(height: 12)
            Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(fg(campaign).opacity(0.6))
        }
    }
}

// MARK: - 2. Star Rating

private struct StarRatingView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let service: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void
    @State private var selected = 0
    @State private var submitted = false

    var body: some View {
        let starCount = icInt(campaign, "rating_scale") ?? 5
        OverlayShell(bgColor: bg(campaign), onDismiss: onDismiss, maxWidth: 320) {
            Text(campaign.title.isEmpty ? "Rate your experience" : campaign.title)
                .font(.system(size: 18, weight: .bold)).foregroundColor(fg(campaign))
            Spacer().frame(height: 16)

            if !submitted {
                HStack(spacing: 8) {
                    ForEach(1...starCount, id: \.self) { i in
                        Text(i <= selected ? "\u{2605}" : "\u{2606}")
                            .font(.system(size: 32))
                            .foregroundColor(i <= selected ? Color(hex: "#FFD700")! : fg(campaign).opacity(0.5))
                            .onTapGesture {
                                selected = i; submitted = true
                                service.submitResponse(campaignId: campaign.id, responseType: "rating",
                                    payload: ["stars": i], variantId: campaign.assignedVariantId) { _ in onAction() }
                            }
                    }
                }
            } else {
                Text("Thanks for rating!").font(.system(size: 14)).foregroundColor(fg(campaign))
            }

            Spacer().frame(height: 12)
            Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(fg(campaign).opacity(0.6))
        }
    }
}

// MARK: - 3. Quick Poll

private struct QuickPollView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let service: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void
    @State private var submitted = false

    var body: some View {
        let options = (icArr(campaign, "poll_options") as? [String]) ?? ["Yes", "No"]
        OverlayShell(bgColor: bg(campaign), onDismiss: onDismiss, maxWidth: 320) {
            Text(campaign.title.isEmpty ? "Quick question" : campaign.title)
                .font(.system(size: 16, weight: .bold)).foregroundColor(fg(campaign))
            Spacer().frame(height: 16)

            if !submitted {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    Button(action: {
                        submitted = true
                        service.submitResponse(campaignId: campaign.id, responseType: "poll",
                            payload: ["option_index": index, "option_label": label],
                            variantId: campaign.assignedVariantId) { _ in onAction() }
                    }) {
                        Text(label).font(.system(size: 14)).foregroundColor(fg(campaign))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(fg(campaign).opacity(0.3), lineWidth: 1))
                    }
                }
            } else {
                Text("Thanks for voting!").font(.system(size: 14)).foregroundColor(fg(campaign))
            }

            Spacer().frame(height: 12)
            Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(fg(campaign).opacity(0.6))
        }
    }
}

// MARK: - 4. Quiz

private struct QuizView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let service: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void
    @State private var currentIndex = 0
    @State private var answers: [[String: Any]] = []
    @State private var finished = false

    var body: some View {
        let questions = (icArr(campaign, "questions") as? [[String: Any]]) ?? []
        let thankYou = icStr(campaign, "thank_you_message") ?? "Thanks for completing the quiz!"

        OverlayShell(bgColor: bg(campaign), onDismiss: onDismiss, maxWidth: 360) {
            Text(campaign.title.isEmpty ? "Quiz" : campaign.title)
                .font(.system(size: 18, weight: .bold)).foregroundColor(fg(campaign))

            if !finished && currentIndex < questions.count {
                let q = questions[currentIndex]
                let qText = q["question"] as? String ?? ""
                let opts = q["options"] as? [String] ?? []

                Text("Question \(currentIndex + 1) of \(questions.count)")
                    .font(.system(size: 12)).foregroundColor(fg(campaign).opacity(0.6))
                Spacer().frame(height: 12)
                Text(qText).font(.system(size: 14, weight: .semibold)).foregroundColor(fg(campaign))
                Spacer().frame(height: 12)

                ForEach(Array(opts.enumerated()), id: \.offset) { optIdx, label in
                    Button(action: {
                        answers.append(["question_index": currentIndex, "answer_index": optIdx])
                        if currentIndex + 1 >= questions.count {
                            finished = true
                            service.submitResponse(campaignId: campaign.id, responseType: "quiz",
                                payload: ["answers": answers], variantId: campaign.assignedVariantId) { _ in onAction() }
                        } else {
                            currentIndex += 1
                        }
                    }) {
                        Text(label).font(.system(size: 14)).foregroundColor(fg(campaign))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(fg(campaign).opacity(0.3), lineWidth: 1))
                    }
                }
            } else {
                Text(thankYou).font(.system(size: 14)).foregroundColor(fg(campaign)).multilineTextAlignment(.center)
            }

            Spacer().frame(height: 12)
            Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(fg(campaign).opacity(0.6))
        }
    }
}

// MARK: - 5. Countdown Offer

private struct CountdownOfferView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let onDismiss: () -> Void
    let onAction: () -> Void

    @State private var remaining: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        let label = icStr(campaign, "countdown_label") ?? "Sale ends in:"
        let targetStr = icStr(campaign, "countdown_target")
        let targetDate: Date = {
            if let str = targetStr, let d = ISO8601DateFormatter().date(from: str) { return d }
            return Date().addingTimeInterval(7200)
        }()

        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        let s = Int(remaining) % 60

        OverlayShell(bgColor: bg(campaign), onDismiss: onDismiss, maxWidth: 320) {
            Text(campaign.title.isEmpty ? "Flash Sale" : campaign.title)
                .font(.system(size: 20, weight: .bold)).foregroundColor(fg(campaign))
            Spacer().frame(height: 8)
            Text(label).font(.system(size: 13)).foregroundColor(fg(campaign).opacity(0.8))
            Spacer().frame(height: 12)

            HStack(spacing: 4) {
                ForEach(
                    [String(format: "%02d", h), ":", String(format: "%02d", m), ":", String(format: "%02d", s)],
                    id: \.self
                ) { seg in
                    if seg == ":" {
                        Text(seg).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(fg(campaign))
                    } else {
                        Text(seg).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(fg(campaign))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(fg(campaign).opacity(0.15)).cornerRadius(8)
                    }
                }
            }

            if !campaign.body.isEmpty {
                Spacer().frame(height: 12)
                Text(campaign.body).font(.system(size: 14)).foregroundColor(fg(campaign).opacity(0.85)).multilineTextAlignment(.center)
            }

            if let btnText = campaign.buttonText {
                Spacer().frame(height: 16)
                Button(action: onAction) {
                    Text(btnText).font(.system(size: 14, weight: .semibold)).foregroundColor(bg(campaign))
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(fg(campaign)).cornerRadius(12)
                }
            }

            Spacer().frame(height: 8)
            Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(fg(campaign).opacity(0.6))
        }
        .onAppear {
            remaining = max(0, targetDate.timeIntervalSinceNow)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                remaining = max(0, targetDate.timeIntervalSinceNow)
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

// MARK: - 6. Multi-Step Form

private struct MultiStepFormView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let service: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void
    @State private var name = ""
    @State private var email = ""
    @State private var feedback = ""
    @State private var submitted = false

    var body: some View {
        let requireEmail = icBool(campaign, "require_email")
        let thankYou = icStr(campaign, "thank_you_message") ?? "Thank you!"

        OverlayShell(bgColor: bg(campaign), onDismiss: onDismiss, maxWidth: 360) {
            Text(campaign.title.isEmpty ? "Quick Form" : campaign.title)
                .font(.system(size: 18, weight: .bold)).foregroundColor(fg(campaign))
            Spacer().frame(height: 16)

            if !submitted {
                TextField("Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle()).autocapitalization(.words)
                if requireEmail {
                    TextField("Email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle()).keyboardType(.emailAddress).autocapitalization(.none)
                }
                TextField("Your feedback", text: $feedback)
                    .textFieldStyle(RoundedBorderTextFieldStyle()).frame(height: 80)

                Spacer().frame(height: 16)
                Button(action: {
                    submitted = true
                    var fields: [String: Any] = ["name": name, "feedback": feedback]
                    if requireEmail { fields["email"] = email }
                    service.submitResponse(campaignId: campaign.id, responseType: "form",
                        payload: ["fields": fields], variantId: campaign.assignedVariantId) { _ in onAction() }
                }) {
                    Text("Submit").font(.system(size: 14, weight: .semibold)).foregroundColor(bg(campaign))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(fg(campaign)).cornerRadius(12)
                }
            } else {
                Text(thankYou).font(.system(size: 14)).foregroundColor(fg(campaign))
            }

            Spacer().frame(height: 8)
            Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(fg(campaign).opacity(0.6))
        }
    }
}

// MARK: - 7. Spin Wheel

private struct SpinWheelView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let service: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void

    @State private var phone = ""
    @State private var email = ""
    @State private var spinning = false
    @State private var rotation: Double = 0
    @State private var prize: [String: Any]? = nil
    @State private var errorMsg: String? = nil

    private let wheelColors: [Color] = [
        Color(hex: "#FF6B6B")!, Color(hex: "#4ECDC4")!,
        Color(hex: "#FFE66D")!, Color(hex: "#95E1D3")!,
        Color(hex: "#A78BFA")!, Color(hex: "#F97316")!
    ]

    var body: some View {
        OverlayShell(bgColor: .white, onDismiss: onDismiss, maxWidth: 360) {
            if let prize = prize {
                PrizeResultView(prize: prize, onClose: onDismiss)
            } else {
                // Wheel
                ZStack {
                    WheelCanvas(colors: wheelColors, segmentCount: 6, rotation: rotation)
                        .frame(width: 220, height: 220)
                    // Pointer
                    Triangle().fill(Color(hex: "#333333")!).frame(width: 20, height: 16)
                        .offset(y: -118)
                }

                Spacer().frame(height: 16)

                TextField("Phone number *", text: $phone).textFieldStyle(RoundedBorderTextFieldStyle()).keyboardType(.phonePad)
                TextField("Email (optional)", text: $email).textFieldStyle(RoundedBorderTextFieldStyle()).keyboardType(.emailAddress).autocapitalization(.none)

                if let err = errorMsg {
                    Text(err).font(.system(size: 12)).foregroundColor(.red)
                }

                Spacer().frame(height: 16)

                Button(action: spinWheel) {
                    Text(spinning ? "Spinning..." : "Spin the Wheel!")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(hex: "#FF6B6B")!).cornerRadius(12)
                }
                .disabled(spinning)

                Spacer().frame(height: 8)
                Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(.gray)
            }
        }
    }

    private func spinWheel() {
        let cleaned = phone.replacingOccurrences(of: "[\\s\\-()]", with: "", options: .regularExpression)
        guard cleaned.range(of: #"^\+?[1-9]\d{1,14}$"#, options: .regularExpression) != nil else {
            errorMsg = "Please enter a valid phone number"
            return
        }
        errorMsg = nil
        spinning = true

        withAnimation(.easeOut(duration: 2)) {
            rotation += 1440 + Double.random(in: 0...360)
        }

        service.submitSpinWheel(phone: cleaned, email: email.isEmpty ? nil : email) { result in
            switch result {
            case .success(let data): prize = data
            case .failure(let err): spinning = false; errorMsg = err.localizedDescription
            }
        }
    }
}

private struct WheelCanvas: View {
    let colors: [Color]
    let segmentCount: Int
    let rotation: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let angle = 2 * .pi / Double(segmentCount)

            for i in 0..<segmentCount {
                let start = Angle(radians: Double(i) * angle + rotation * .pi / 180 - .pi / 2)
                let end = Angle(radians: Double(i + 1) * angle + rotation * .pi / 180 - .pi / 2)
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(colors[i % colors.count]))
            }
            // Center dot
            var dot = Path()
            dot.addEllipse(in: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
            context.fill(dot, with: .color(.white))
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

// MARK: - 8. Scratch Card

private struct ScratchCardView: View {
    let campaign: AegisInAppManager.InAppCampaign
    let service: InAppResponseService
    let onDismiss: () -> Void
    let onAction: () -> Void
    @State private var prize: [String: Any]? = nil
    @State private var revealing = false
    @State private var errorMsg: String? = nil
    @State private var scratchPoints: [CGPoint] = []

    var body: some View {
        OverlayShell(bgColor: .white, onDismiss: onDismiss, maxWidth: 340) {
            if let prize = prize {
                PrizeResultView(prize: prize, onClose: onDismiss)
            } else {
                Text(campaign.title.isEmpty ? "Scratch & Win!" : campaign.title)
                    .font(.system(size: 20, weight: .bold)).foregroundColor(.black)
                Text("Scratch the card to reveal your prize!").font(.system(size: 13)).foregroundColor(.gray)
                Spacer().frame(height: 16)

                // Scratch area
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#F0F0F0")!).frame(height: 160)
                        .overlay(Text("?").font(.system(size: 48, weight: .bold)).foregroundColor(.gray.opacity(0.3)))

                    Canvas { context, size in
                        // Gray cover
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#C0C0C0")!))
                        // Scratch holes
                        for point in scratchPoints {
                            context.blendMode = .clear
                            var circle = Path()
                            circle.addEllipse(in: CGRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40))
                            context.fill(circle, with: .color(.clear))
                        }
                        // Text
                        if scratchPoints.isEmpty {
                            context.draw(Text("Scratch here!").font(.system(size: 18)).foregroundColor(.gray),
                                at: CGPoint(x: size.width / 2, y: size.height / 2))
                        }
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        scratchPoints.append(value.location)
                    })
                }

                if let err = errorMsg {
                    Text(err).font(.system(size: 12)).foregroundColor(.red)
                }

                Spacer().frame(height: 16)

                Button(action: {
                    revealing = true
                    service.generateScratchPrize(configId: campaign.id) { result in
                        switch result {
                        case .success(let data): prize = data
                        case .failure(let err): revealing = false; errorMsg = err.localizedDescription
                        }
                    }
                }) {
                    Text(revealing ? "REVEALING..." : "REVEAL PRIZE")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(hex: "#F5576C")!).cornerRadius(12)
                }
                .disabled(revealing)

                Spacer().frame(height: 8)
                Button("Close") { onDismiss() }.font(.system(size: 12)).foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Shared Prize Result

private struct PrizeResultView: View {
    let prize: [String: Any]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("\u{1F389}").font(.system(size: 48))
            Text("Congratulations!").font(.system(size: 24, weight: .bold)).foregroundColor(Color(hex: "#1A73E8")!)

            Text(prize["prize_label"] as? String ?? "You won!")
                .font(.system(size: 18, weight: .semibold)).foregroundColor(.black)

            if let code = prize["coupon_code"] as? String {
                VStack(spacing: 4) {
                    Text("Your coupon code:").font(.system(size: 12)).foregroundColor(.gray)
                    Text(code).font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#1A73E8")!).tracking(2)
                }
                .padding(16)
                .background(Color(hex: "#F5F5F5")!)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#1A73E8")!, style: StrokeStyle(lineWidth: 1, dash: [5])))
                .cornerRadius(8)
            }

            Spacer().frame(height: 16)
            Button(action: onClose) {
                Text("Close").foregroundColor(.white).padding(.horizontal, 32).padding(.vertical, 10)
                    .background(Color(hex: "#1A73E8")!).cornerRadius(12)
            }
        }
    }
}
