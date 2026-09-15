import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var exportResult: FlutterResult?
  private var exportDirectory: URL?

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishExport(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finishExport(urls.first?.absoluteString)
  }

  private func finishExport(_ value: Any?) {
    let callback = exportResult
    exportResult = nil
    if let directory = exportDirectory { try? FileManager.default.removeItem(at: directory) }
    exportDirectory = nil
    callback?(value)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EkkoFileExport")!
    let channel = FlutterMethodChannel(name: "ai.ekkolearn.ekko_app/file_export", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      guard call.method == "save" else { result(FlutterMethodNotImplemented); return }
      guard self.exportResult == nil else { result(FlutterError(code: "busy", message: "已有文件正在保存", details: nil)); return }
      guard let args = call.arguments as? [String: String], let path = args["path"] else {
        result(FlutterError(code: "path", message: "无效文件", details: nil)); return
      }
      let source = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
      guard source.path.hasPrefix(home), FileManager.default.fileExists(atPath: source.path) else {
        result(FlutterError(code: "path", message: "只允许导出 App 临时文件", details: nil)); return
      }
      self.exportResult = result
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let name = (args["name"] ?? "attachment").components(separatedBy: CharacterSet(charactersIn: "/\\").union(.controlCharacters)).joined(separator: "_")
          let target = directory.appendingPathComponent(name.isEmpty ? "attachment" : name)
          try FileManager.default.copyItem(at: source, to: target)
          DispatchQueue.main.async {
            self.exportDirectory = directory
            let picker = UIDocumentPickerViewController(forExporting: [target], asCopy: true)
            picker.delegate = self
            var presenter = self.window?.rootViewController
            while let presented = presenter?.presentedViewController { presenter = presented }
            guard let presenter = presenter else { self.finishExport(FlutterError(code: "export", message: "无法打开保存对话框", details: nil)); return }
            presenter.present(picker, animated: true)
          }
        } catch {
          try? FileManager.default.removeItem(at: directory)
          DispatchQueue.main.async { self.finishExport(FlutterError(code: "export", message: "保存失败，请检查存储空间", details: nil)) }
        }
      }
    }
  }
}
