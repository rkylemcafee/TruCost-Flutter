import Flutter
import UIKit
import GoogleMaps
import PDFKit
import Vision
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The key comes from ios/Flutter/Secrets.xcconfig through Info.plist, so it
    // is never in git. Without it the live turn map draws a grey grid.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SurveyDocPlugin") {
      SurveyDocPlugin.register(with: registrar)
    }
  }
}

/// Reading a state's route survey off paper or out of a PDF.
///
/// Both answers come back in the same shape — words with a position on the
/// page, y increasing upward — because that is what the column-keeping layout
/// in lib/survey/import/pdf_text.dart was written against. A route survey is a
/// table, and words without their positions are a table with the columns gone.
final class SurveyDocPlugin: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
  private var pendingScan: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "trucost/survey_doc", binaryMessenger: registrar.messenger())
    let instance = SurveyDocPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "pdfFragments":
      guard let path = args["path"] as? String else { return result(nil) }
      DispatchQueue.global(qos: .userInitiated).async {
        let pages = Self.pdfFragments(path: path)
        DispatchQueue.main.async { result(pages) }
      }
    case "ocrFragments":
      let paths = args["paths"] as? [String] ?? []
      DispatchQueue.global(qos: .userInitiated).async {
        let pages = paths.map { Self.ocrFragments(path: $0) }
        DispatchQueue.main.async { result(pages) }
      }
    case "scanDocument":
      guard VNDocumentCameraViewController.isSupported, let top = Self.topController() else {
        return result(FlutterError(code: "unsupported", message: "This device cannot scan documents.", details: nil))
      }
      pendingScan = result
      let scanner = VNDocumentCameraViewController()
      scanner.delegate = self
      top.present(scanner, animated: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: PDF

  /// One fragment per word, at the word's own position.
  ///
  /// PDFKit hands out the page's text and the box of every character in it.
  /// Words are runs of non-space characters on one baseline; the layout code
  /// puts each at the column its x falls in, so the gaps between columns
  /// survive however many spaces the PDF itself bothered to store.
  static func pdfFragments(path: String) -> [[[String: Any]]] {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else { return [] }
    var out: [[[String: Any]]] = []
    for n in 0..<doc.pageCount {
      guard let page = doc.page(at: n), let text = page.string as NSString? else { out.append([]); continue }
      var frags: [[String: Any]] = []
      var word = ""
      var box = CGRect.null
      func flush() {
        if !word.isEmpty && !box.isNull {
          frags.append(["x": box.minX, "y": box.minY, "w": box.width, "s": word])
        }
        word = ""; box = .null
      }
      for i in 0..<text.length {
        let ch = text.substring(with: NSRange(location: i, length: 1))
        if ch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { flush(); continue }
        let b = page.characterBounds(at: i)
        // A new baseline is a new word even with no space between them.
        if !box.isNull && abs(b.minY - box.minY) > 2 { flush() }
        word += ch
        box = box.isNull ? b : box.union(b)
      }
      flush()
      out.append(frags)
    }
    return out
  }

  // MARK: Photo

  /// Words read off a photograph of a paper survey.
  ///
  /// Vision gives boxes as fractions of the image. They are scaled so a line
  /// of text is about nine units tall, the size of print on a PDF page, which
  /// lets the same "same line" tolerance work for both.
  static func ocrFragments(path: String) -> [[String: Any]] {
    guard let image = UIImage(contentsOfFile: path)?.cgImage else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    // Road names are not English. Correction turns "SR-69" into words.
    request.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    let lines = (request.results ?? []).compactMap { obs -> (VNRecognizedTextObservation, VNRecognizedText)? in
      guard let top = obs.topCandidates(1).first else { return nil }
      return (obs, top)
    }
    if lines.isEmpty { return [] }

    let heights = lines.map { $0.0.boundingBox.height }.sorted()
    let lineH = max(heights[heights.count / 2], 0.001)
    let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
    let sy = 9 / lineH
    // Box x is a fraction of the width and y of the height; scale both into
    // the same square units so a character is as wide as it looks.
    let sx = sy / aspect

    var frags: [[String: Any]] = []
    for (obs, text) in lines {
      let s = text.string as NSString
      // Every word in one recognised line shares that line's baseline; a
      // slightly tilted photo should not split one row into two.
      let y = obs.boundingBox.minY * sy
      var start = -1
      for i in 0...s.length {
        let isSpace = i == s.length || s.substring(with: NSRange(location: i, length: 1)) == " "
        if !isSpace && start < 0 { start = i }
        if isSpace && start >= 0 {
          let range = NSRange(location: start, length: i - start)
          let word = s.substring(with: range)
          var bb = obs.boundingBox
          if let r = Range(range, in: text.string), let box = try? text.boundingBox(for: r) {
            bb = box.boundingBox
          }
          frags.append(["x": bb.minX * sx, "y": y, "w": bb.width * sx, "s": word])
          start = -1
        }
      }
    }
    return frags
  }

  // MARK: Scanner

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    var paths: [String] = []
    let dir = FileManager.default.temporaryDirectory
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    for i in 0..<scan.pageCount {
      let url = dir.appendingPathComponent("survey-scan-\(stamp)-\(i + 1).jpg")
      if let data = scan.imageOfPage(at: i).jpegData(compressionQuality: 0.85), (try? data.write(to: url)) != nil {
        paths.append(url.path)
      }
    }
    controller.dismiss(animated: true)
    pendingScan?(paths)
    pendingScan = nil
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    pendingScan?([String]())
    pendingScan = nil
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    controller.dismiss(animated: true)
    pendingScan?(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
    pendingScan = nil
  }

  private static func topController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
      .first
    var top = window?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
  }
}
