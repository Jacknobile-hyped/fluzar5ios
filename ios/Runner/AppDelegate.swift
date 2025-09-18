import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Osserva quando l’app diventa attiva per aggiornare l’icona
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(updateIcon),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc func updateIcon() {
    guard UIApplication.shared.supportsAlternateIcons else { return }
    let style = window?.traitCollection.userInterfaceStyle ?? .light

    // Usa "AppIconDark" come nome del set alternativo negli Assets.xcassets
    let targetIcon = (style == .dark) ? "AppIconDark" : nil

    if UIApplication.shared.alternateIconName != targetIcon {
      UIApplication.shared.setAlternateIconName(targetIcon) { error in
        if let e = error {
          print("Errore cambio icona: \(e.localizedDescription)")
        }
      }
    }
  }
}
