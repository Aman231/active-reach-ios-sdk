import SwiftUI
import ActiveReachSDK

struct ContentView: View {

    @State private var status: String = "Ready"
    @State private var marketingOptIn: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section("Identity") {
                    Button("Identify user_demo_123") {
                        Aegis.shared.identify("user_demo_123", traits: [
                            "email": "demo@example.com",
                            "plan": "pro"
                        ])
                        status = "Identified user_demo_123"
                    }
                    Button("Reset (logout)") {
                        Aegis.shared.reset()
                        status = "Identity reset"
                    }
                }

                Section("Tracking") {
                    Button("track screen_viewed") {
                        Aegis.shared.screen("Home")
                        status = "Tracked screen_viewed"
                    }
                    Button("track button_clicked") {
                        Aegis.shared.track("button_clicked", properties: [
                            "name": "demo_btn"
                        ])
                        status = "Tracked button_clicked"
                    }
                }

                Section("E-commerce") {
                    Button("productViewed") {
                        Aegis.shared.ecommerce.productViewed(
                            id: "sku_001",
                            name: "Sample T-shirt",
                            price: 1499,
                            currency: "INR",
                            category: "Apparel"
                        )
                        status = "Tracked productViewed"
                    }
                    Button("addToCart") {
                        Aegis.shared.ecommerce.productAddedToCart(
                            id: "sku_001",
                            name: "Sample T-shirt",
                            quantity: 1,
                            price: 1499,
                            currency: "INR"
                        )
                        status = "Tracked addToCart"
                    }
                }

                Section("In-app") {
                    Button("Trigger 'welcome_modal' campaign") {
                        Aegis.shared.track("trigger_modal")
                        status = "Triggered welcome_modal"
                    }
                }

                Section("Consent") {
                    Toggle("Marketing consent", isOn: $marketingOptIn)
                        .onChange(of: marketingOptIn) { granted in
                            Aegis.shared.consent.setConsent(
                                analytics: true,
                                marketing: granted,
                                personalisation: true,
                                functional: true
                            )
                            status = "Marketing consent = \(granted)"
                        }
                }

                Section("Status") {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Active Reach Demo")
        }
    }
}

#Preview {
    ContentView()
}
