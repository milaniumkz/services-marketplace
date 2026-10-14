import Flutter
import UIKit
import Security
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var fileExporter: JobaFileExporter?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      fileExporter = JobaFileExporter(controller: controller)
      let sharing = FlutterMethodChannel(name: "joba.share", binaryMessenger: controller.binaryMessenger)
      sharing.setMethodCallHandler { [weak controller] call, result in
        guard call.method == "text" else { result(FlutterMethodNotImplemented); return }
        guard let controller = controller, let args = call.arguments as? [String: String], let text = args["text"], !text.isEmpty, text.count <= 2000 else { result(FlutterError(code: "SHARE_INVALID", message: "Invalid invitation", details: nil)); return }
        guard controller.presentedViewController == nil else { result(FlutterError(code: "SHARE_BUSY", message: "Close the current dialog", details: nil)); return }
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController { popover.sourceView = controller.view; popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1) }
        controller.present(sheet, animated: true) { result(nil) }
      }

      let channel = FlutterMethodChannel(name: "joba.device_security", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "hardwareBacked" else {
          self.biometry(call, result: result); return
        }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.privateKeyUsage], &error) else { result(false); return }
        let attributes: [String: Any] = [
          kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
          kSecAttrKeySizeInBits as String: 256,
          kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
          kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false, kSecAttrAccessControl as String: access]
        ]
        result(SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  private func biometry(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: String], let alias = args["alias"],
      alias.hasPrefix("joba.biometry."), alias.count == 78 else { result(FlutterMethodNotImplemented); return }
    DispatchQueue.global(qos: .userInitiated).async {
      let tag = Data(alias.utf8)
      let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag,
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom]
      var reply: Any? = false
      if call.method == "clearBiometry" { SecItemDelete(query as CFDictionary); reply = true }
      else if call.method == "enableBiometry" {
        let context = LAContext()
        var policyError: NSError?
        if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) {
          reply = FlutterError(code: "BIOMETRY_UNAVAILABLE", message: "Биометрия недоступна", details: nil)
        } else {
          var error: Unmanaged<CFError>?
          guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], &error) else {
              DispatchQueue.main.async { result(false) }; return
          }
          SecItemDelete(query as CFDictionary)
          let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256, kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true,
              kSecAttrApplicationTag as String: tag, kSecAttrAccessControl as String: access]]
          reply = SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil
        }
      } else if call.method == "checkBiometry" || call.method == "unlockBiometry" {
        var lookup = query
        lookup[kSecReturnRef as String] = true
        if call.method == "checkBiometry" { lookup[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        else { lookup[kSecUseOperationPrompt as String] = args["title"] ?? "JOBA" }
        var reference: CFTypeRef?
        let code = SecItemCopyMatching(lookup as CFDictionary, &reference)
        if code == errSecItemNotFound {
          reply = FlutterError(code: "BIOMETRY_CHANGED", message: "Биометрия изменилась. Войдите снова с паролем", details: nil)
        } else if call.method == "checkBiometry" { reply = code == errSecSuccess || code == errSecInteractionNotAllowed }
        else if code == errSecSuccess, let ref = reference {
          let key = ref as! SecKey
          var error: Unmanaged<CFError>?
          reply = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, Data(UUID().uuidString.utf8) as CFData, &error) != nil
        }
      } else { reply = FlutterMethodNotImplemented }
      DispatchQueue.main.async { result(reply) }
    }
  }
}


private final class JobaFileExporter: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private weak var presenter: UIViewController?
  private var pending: FlutterResult?
  private var channel: FlutterMethodChannel
  init(controller: FlutterViewController) {
    presenter = controller
    channel = FlutterMethodChannel(name: "joba.file_export", binaryMessenger: controller.binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "EXPORT_UNAVAILABLE", message: "Exporter unavailable", details: nil)); return }
      guard call.method == "save" else { result(FlutterMethodNotImplemented); return }
      guard self.pending == nil else { result(FlutterError(code: "EXPORT_BUSY", message: "Another export is active", details: nil)); return }
      guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else { result(FlutterError(code: "EXPORT_INVALID", message: "Invalid export", details: nil)); return }
      let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      let roots = [URL(fileURLWithPath: NSTemporaryDirectory())] + FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      guard roots.contains(where: { url.path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }), FileManager.default.fileExists(atPath: url.path), let presenter = self.presenter else { result(FlutterError(code: "EXPORT_INVALID", message: "Invalid private export file", details: nil)); return }
      guard UIApplication.shared.applicationState == .active, presenter.viewIfLoaded?.window != nil else { result(FlutterError(code: "EXPORT_UNAVAILABLE", message: "Open the application to save the export", details: nil)); return }
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
      else { picker = UIDocumentPickerViewController(url: url, in: .exportToService) }
      picker.delegate = self
      self.pending = result
      presenter.present(picker, animated: true) { picker.presentationController?.delegate = self }
    }
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pending; pending = nil; result?(!urls.isEmpty)
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { let result = pending; pending = nil; result?(false) }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pending; pending = nil; result?(false)
  }
}
