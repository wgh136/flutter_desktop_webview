//
//  WebviewWindowController.swift
//  webview_window
//
//  Created by Bin Yang on 2021/10/15.
//

import Cocoa
import FlutterMacOS
import WebKit

class WebviewWindowController: NSWindowController {
  @IBOutlet var webview: WKWebView!

  private let viewId: Int64

  private let methodChannel: FlutterMethodChannel

  private var javaScriptHandlerNames: [String] = []

  private let width: Int
  private let height: Int

  private let initialTitle: String

  weak var webviewPlugin: DesktopWebviewWindowPlugin?

  init(viewId: Int64, methodChannel: FlutterMethodChannel,
       width: Int, height: Int,
       title: String) {
    self.viewId = viewId
    self.methodChannel = methodChannel
    self.width = width
    self.height = height
    self.initialTitle = title
    super.init(window: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func windowDidLoad() {
    super.windowDidLoad()

    window?.isReleasedWhenClosed = true
    window?.delegate = self

    window?.setContentSize(NSSize(width: width, height: height))
    window?.center()
    
    window?.title = initialTitle

    webview.navigationDelegate = self
    webview.uiDelegate = self

    // TODO(boyan01) Make it configuable from flutter.
    webview.configuration.preferences.javaEnabled = true
    webview.configuration.preferences.minimumFontSize = 12
    webview.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    webview.configuration.allowsAirPlayForMediaPlayback = true
    webview.configuration.mediaTypesRequiringUserActionForPlayback = .video
  }

  func load(url: URL) {
    webview.load(URLRequest(url: url))
  }

  func addJavascriptInterface(name: String) {
    javaScriptHandlerNames.append(name)
    webview.configuration.userContentController.add(self, name: name)
  }

  func removeJavascriptInterface(name: String) {
    if let index = javaScriptHandlerNames.firstIndex(of: name) {
      javaScriptHandlerNames.remove(at: index)
    }
    webview.configuration.userContentController.removeScriptMessageHandler(forName: name)
  }

  func destroy() {
    webview.removeFromSuperview()
    webview.uiDelegate = nil
    webview.navigationDelegate = nil
    javaScriptHandlerNames.forEach { name in
      webview.configuration.userContentController.removeScriptMessageHandler(forName: name)
    }

    webview.configuration.userContentController.removeAllUserScripts()
  }

  func setAppearance(brightness: Int) {
    switch brightness {
    case 0:
      if #available(macOS 10.14, *) {
        window?.appearance = NSAppearance(named: .darkAqua)
      } else {
        // Fallback on earlier versions
      }
      break
    case 1:
      window?.appearance = NSAppearance(named: .aqua)
      break
    default:
      window?.appearance = nil
      break
    }
  }

  deinit {
    #if DEBUG
      print("\(self) deinited")
    #endif
  }

  override var windowNibName: NSNib.Name? {
    "WebviewWindowController"
  }
}

extension WebviewWindowController: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    methodChannel.invokeMethod("onWindowClose", arguments: ["id": viewId])
    DispatchQueue.main.async {
      self.webviewPlugin?.onWebviewWindowClose(viewId: self.viewId, wc: self)
    }
  }
}

extension WebviewWindowController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    methodChannel.invokeMethod(
      "onJavaScriptMessage",
      arguments: [
        "id": viewId,
        "name": message.name,
        "body": message.body,
      ])
  }
}

extension WebviewWindowController: WKNavigationDelegate {
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }

    guard ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else {
      decisionHandler(.cancel)
      return
    }

    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    decisionHandler(.allow)
  }
}

extension WebviewWindowController: WKUIDelegate {
  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    methodChannel.invokeMethod(
      "runJavaScriptTextInputPanelWithPrompt",
      arguments: [
        "id": viewId,
        "prompt": prompt,
        "defaultText": defaultText ?? "",
      ]) { result in
      completionHandler((result as? String) ?? "")
    }
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if !(navigationAction.targetFrame?.isMainFrame ?? false) {
      webView.load(navigationAction.request)
    }
    return nil
  }
}
