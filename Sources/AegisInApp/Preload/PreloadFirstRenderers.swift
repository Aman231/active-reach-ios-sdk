#if canImport(UIKit)
import UIKit

/// Phase 3.5 — MVP renderers for the 5 preload-first in-app render
/// types from web SDK (2026-04-22). Each renderer consumes the
/// canonical campaign payload pinned by
/// the cross-SDK drift contract and
/// renders with UIKit native widgets.
///
/// Visual polish is Phase 3.6 — these are intentionally minimal so
/// we ship the wire contract first.
public enum PreloadFirstRenderers {

    public typealias LifecycleListener = (_ campaignId: String, _ event: String, _ properties: [String: Any]) -> Void

    /// Dispatch entrypoint — routes a campaign's `type` to the right
    /// renderer. Returns true when the type was recognised.
    @discardableResult
    public static func render(
        on presenter: UIViewController,
        campaignId: String,
        type: String,
        config: [String: Any],
        listener: @escaping LifecycleListener
    ) -> Bool {
        switch type {
        case "carousel_cards":         return CarouselCardsRenderer.show(on: presenter, campaignId: campaignId, config: config, listener: listener)
        case "sticky_bar":             return StickyBarRenderer.show(on: presenter, campaignId: campaignId, config: config, listener: listener)
        case "progress_bar":           return ProgressBarRenderer.show(on: presenter, campaignId: campaignId, config: config, listener: listener)
        case "coachmark_tour":         return CoachmarkTourRenderer.show(on: presenter, campaignId: campaignId, config: config, listener: listener)
        case "product_recommendation": return ProductRecommendationRenderer.show(on: presenter, campaignId: campaignId, config: config, listener: listener)
        default: return false
        }
    }
}

// MARK: - carousel_cards

public enum CarouselCardsRenderer {
    public static func show(on presenter: UIViewController, campaignId: String, config: [String: Any], listener: @escaping PreloadFirstRenderers.LifecycleListener) -> Bool {
        guard let cards = config["cards"] as? [[String: Any]], !cards.isEmpty else { return false }
        func renderAt(_ index: Int) {
            let card = cards[index]
            let alert = UIAlertController(
                title: card["title"] as? String,
                message: card["body"] as? String,
                preferredStyle: .alert
            )
            let ctaTitle = (card["button_text"] as? String) ?? (index + 1 < cards.count ? "Next" : "Done")
            alert.addAction(UIAlertAction(title: ctaTitle, style: .default) { _ in
                let actionUrl = card["action_url"] as? String ?? ""
                listener(campaignId, "in_app.clicked", ["position": index, "action_url": actionUrl])
                if let url = URL(string: actionUrl), !actionUrl.isEmpty {
                    UIApplication.shared.open(url)
                }
                if index + 1 < cards.count { renderAt(index + 1) }
            })
            alert.addAction(UIAlertAction(title: "Skip", style: .cancel) { _ in
                listener(campaignId, "in_app.dismissed", ["position": index])
            })
            presenter.present(alert, animated: true)
            if index == 0 {
                listener(campaignId, "in_app.displayed", ["card_count": cards.count])
            }
        }
        renderAt(0)
        return true
    }
}

// MARK: - sticky_bar

public enum StickyBarRenderer {
    public static func show(on presenter: UIViewController, campaignId: String, config: [String: Any], listener: @escaping PreloadFirstRenderers.LifecycleListener) -> Bool {
        let text = (config["body"] as? String) ?? (config["title"] as? String) ?? ""
        guard !text.isEmpty else { return false }
        let position = (config["position"] as? String) ?? "bottom"
        let bgColor = parseColor((config["bg_color"] as? String) ?? "#212121")
        let dismissible = (config["dismissible"] as? Bool) ?? true
        let autoHideMs = config["auto_hide_ms"] as? Double ?? 0
        let actionUrl = (config["action_url"] as? String) ?? ""

        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = bgColor
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -40),
            label.topAnchor.constraint(equalTo: bar.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -12),
        ])
        if dismissible {
            let close = UIButton(type: .system)
            close.setTitle("✕", for: .normal)
            close.tintColor = .white
            close.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(close)
            NSLayoutConstraint.activate([
                close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
                close.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            ])
            close.addAction(UIAction { _ in
                listener(campaignId, "in_app.dismissed", [:])
                bar.removeFromSuperview()
            }, for: .touchUpInside)
        }
        if !actionUrl.isEmpty {
            let tap = UITapGestureRecognizer()
            label.isUserInteractionEnabled = true
            tap.addTarget(NSObject(), action: #selector(NSObject.copy as () -> Any))  // placeholder; replaced below
            label.addGestureRecognizer(tap)
            // Use a closure-friendly target instead:
            label.gestureRecognizers?.removeAll()
            let target = TapTarget {
                listener(campaignId, "in_app.clicked", ["action_url": actionUrl])
                if let url = URL(string: actionUrl) { UIApplication.shared.open(url) }
            }
            objc_setAssociatedObject(label, &TapTarget.key, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            label.addGestureRecognizer(UITapGestureRecognizer(target: target, action: #selector(TapTarget.fire)))
        }
        let host = presenter.view!
        host.addSubview(bar)
        if position == "top" {
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                bar.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor),
            ])
        }
        listener(campaignId, "in_app.displayed", ["position": position])
        if autoHideMs > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHideMs / 1000.0) {
                bar.removeFromSuperview()
            }
        }
        return true
    }
}

// MARK: - progress_bar

public enum ProgressBarRenderer {
    public static func show(on presenter: UIViewController, campaignId: String, config: [String: Any], listener: @escaping PreloadFirstRenderers.LifecycleListener) -> Bool {
        let current = (config["current"] as? Double) ?? 0
        let target = max((config["target"] as? Double) ?? 1, 0.0001)
        let labelTemplate = (config["label_format"] as? String) ?? "{current} of {target}"
        let barColor = parseColor((config["color"] as? String) ?? "#4169E1")

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .white
        let label = UILabel()
        label.text = labelTemplate
            .replacingOccurrences(of: "{current}", with: "\(Int(current))")
            .replacingOccurrences(of: "{target}", with: "\(Int(target))")
        label.translatesAutoresizingMaskIntoConstraints = false
        let bar = UIProgressView(progressViewStyle: .bar)
        bar.progress = Float(current / target)
        bar.progressTintColor = barColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        let host = presenter.view!
        host.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            container.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor),
        ])
        listener(campaignId, "in_app.displayed", ["current": current, "target": target])
        return true
    }
}

// MARK: - coachmark_tour

public enum CoachmarkTourRenderer {
    public static func show(on presenter: UIViewController, campaignId: String, config: [String: Any], listener: @escaping PreloadFirstRenderers.LifecycleListener) -> Bool {
        guard let steps = config["steps"] as? [[String: Any]], !steps.isEmpty else { return false }
        let skipEnabled = (config["skip_enabled"] as? Bool) ?? true
        func renderStep(_ i: Int) {
            let step = steps[i]
            let alert = UIAlertController(
                title: step["title"] as? String,
                message: step["body"] as? String,
                preferredStyle: .alert
            )
            let isLast = (i + 1 == steps.count)
            alert.addAction(UIAlertAction(title: isLast ? "Done" : "Next", style: .default) { _ in
                listener(campaignId, "in_app.clicked", ["step": i, "step_count": steps.count])
                if !isLast { renderStep(i + 1) }
                else { listener(campaignId, "in_app.dismissed", ["completed": true]) }
            })
            if skipEnabled {
                alert.addAction(UIAlertAction(title: "Skip", style: .cancel) { _ in
                    listener(campaignId, "in_app.dismissed", ["completed": false, "step": i])
                })
            }
            presenter.present(alert, animated: true)
            if i == 0 {
                listener(campaignId, "in_app.displayed", ["step_count": steps.count])
            }
        }
        renderStep(0)
        return true
    }
}

// MARK: - product_recommendation

public enum ProductRecommendationRenderer {
    public static func show(on presenter: UIViewController, campaignId: String, config: [String: Any], listener: @escaping PreloadFirstRenderers.LifecycleListener) -> Bool {
        guard let products = config["products"] as? [[String: Any]], !products.isEmpty else { return false }
        let title = (config["title"] as? String) ?? "Recommended for you"
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (i, p) in products.enumerated() {
            let name = p["name"] as? String ?? ""
            let price = p["price"] as? Double ?? 0
            let currency = (p["currency"] as? String) ?? "INR"
            alert.addAction(UIAlertAction(title: "\(name) — \(currency) \(price)", style: .default) { _ in
                listener(campaignId, "in_app.clicked", [
                    "product_id": p["product_id"] ?? "",
                    "position": i,
                ])
            })
        }
        alert.addAction(UIAlertAction(title: "Close", style: .cancel) { _ in
            listener(campaignId, "in_app.dismissed", [:])
        })
        presenter.present(alert, animated: true)
        listener(campaignId, "in_app.displayed", ["product_count": products.count])
        return true
    }
}

// MARK: - helpers

private final class TapTarget: NSObject {
    static var key: UInt8 = 0
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

private func parseColor(_ hex: String) -> UIColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let rgb = UInt32(s, radix: 16) else { return .darkGray }
    return UIColor(
        red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgb & 0x0000FF) / 255.0,
        alpha: 1.0
    )
}
#endif
