import Flutter
import UIKit
import Security
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
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
        else { lookup[kSecUseOperationPrompt as String] = "Разблокировка сохранённой сессии JOBA" }
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
