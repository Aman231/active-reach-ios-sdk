Pod::Spec.new do |s|
  s.name             = 'ActiveReachSDK'
  s.version          = '1.6.0'
  s.summary          = 'Active Reach iOS SDK — event tracking, identity, consent, governance'
  s.description      = <<-DESC
    Official iOS SDK for the Active Reach Platform. This 1.6.0 release
    ships the Core module:

      • Event tracking (track / screen / page)
      • Identity resolution + sessions
      • E-commerce tracker (19 canonical events)
      • Consent management (4 canonical categories)
      • Trait & event-name governance (client-side guards)
      • Multi-region cell routing
      • Plugin extension surface

    Push notifications, in-app messaging, NSE, and location ship as
    separate SPM products from the same repo. CocoaPods subspecs for
    Push / InApp / NotificationService / Location land in a patch
    release once their compile-time API alignment is complete.

    Source: https://github.com/Aman231/active-reach-ios-sdk
  DESC

  s.homepage         = 'https://github.com/Aman231/active-reach-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Active Reach' => 'sdk@active-reach.ai' }
  s.source           = { :git => 'https://github.com/Aman231/active-reach-ios-sdk.git', :tag => s.version.to_s }
  s.documentation_url = 'https://docs.active-reach.ai/developers/sdks/ios-sdk'

  s.ios.deployment_target = '13.0'
  s.swift_version    = '5.9'
  s.module_name      = 'ActiveReachSDK'

  s.source_files = 'Sources/AegisCore/**/*.swift'
  s.frameworks   = 'Foundation', 'UIKit', 'CoreTelephony', 'SystemConfiguration'
  s.dependency 'SQLite.swift', '~> 0.14.1'

  # Apple App Store privacy manifest — required for iOS 17+ third-party
  # SDKs. Declares User ID / Device ID / Product Interaction collection
  # and UserDefaults access (CA92.1).
  s.resource_bundles = {
    'ActiveReachSDK' => ['Sources/AegisCore/Resources/PrivacyInfo.xcprivacy']
  }
end
