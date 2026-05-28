import SwiftUI
import ActiveReachSDK
import ActiveReachInApp
import ActiveReachPush
import UserNotifications

@main
struct SwiftUIStarterApp: App {

    init() {
        // 1. Initialize the SDK as early as possible.
        Aegis.shared.initialize(
            writeKey: "pk_live_xxx", // replace with your write key
            config: AegisConfig(
                apiHost: "https://api.active-reach.ai",
                encryptLocalStorage: true,
                autoSessionTracking: true,
                enableRemoteConfig: true
            )
        )

        // 2. Start in-app messaging.
        AegisInAppManager.shared.start()

        // 3. Request push permission.
        registerForPush()

        // 4. Default consent state — flip these based on your in-app
        //    consent UI. Marketing defaults to false until granted.
        Aegis.shared.consent.setConsent(
            analytics: true,
            marketing: false,
            personalisation: true,
            functional: true
        )

        // 5. Track app open.
        Aegis.shared.track("app_opened", properties: [
            "channel": "organic"
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func registerForPush() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
