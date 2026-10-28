import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private var voipRegistry: PKPushRegistry?
  /// calls answered on this phone (a cancel for them is never acted on) and calls being ended by a cancel (their end
  /// is not a Decline to report to the server)
  private var answered = Set<String>()
  private var cancelling = Set<String>()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // VoIP pushes (incoming calls) wake the app even when it was closed; see pushRegistry(_:didReceiveIncomingPushWith:)
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    // With the implicit engine, plugins are registered after launch, so firebase_messaging and
    // flutter_local_notifications miss this callback: claim the notification delegate (FlutterAppDelegate
    // forwards it to them, so taps and foreground pushes reach Dart) and ask for the APNs token here,
    // which Firebase needs before it hands out the FCM token used for message notifications.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // "webweb/call" (call_manager.dart): screen off at the ear on voice calls, screen kept on for video.
    // The ongoing call itself (status bar, lock screen, background audio) is CallKit's.
    let channel = FlutterMethodChannel(name: "webweb/call", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      switch call.method {
      case "proximity": UIDevice.current.isProximityMonitoringEnabled = on
      case "awake": UIApplication.shared.isIdleTimerDisabled = on
      case "service": break // Android only
      default: return result(FlutterMethodNotImplemented)
      }
      result(nil)
    }
  }

  // MARK: PushKit

  /// The token is passed to Dart (NativeCalls.voipToken / the token-updated event), which sends it to the API.
  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  /// An incoming call from the API (`{ type: "call", callId, from, name, handle, photo, video }`).
  /// iOS requires every VoIP push to be reported to CallKit right away, before Flutter has started.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP, let callkit = SwiftFlutterCallkitIncomingPlugin.sharedInstance else { return completion() }
    let p = payload.dictionaryPayload
    // the caller hung up, or another phone answered or declined: stop this one ringing
    if (p["type"] as? String) == "call_cancel" {
      return cancelCall(callkit, callId: (p["callId"] as? String) ?? "", completion: completion)
    }
    let id = (p["callId"] as? String) ?? UUID().uuidString
    let name = (p["name"] as? String) ?? "WEBWEB AI"
    let handle = (p["handle"] as? String).map { $0.isEmpty ? "" : "@\($0)" } ?? ""
    let video = (p["video"] as? String) == "true"

    let data = flutter_callkit_incoming.Data(id: id, nameCaller: name, handle: handle.isEmpty ? (video ? "Video call" : "Voice call") : handle, type: video ? 1 : 0)
    data.appName = "WEBWEB AI"
    data.avatar = (p["photo"] as? String) ?? ""
    data.duration = 45000
    data.supportsVideo = true
    data.handleType = "generic"
    data.includesCallsInRecents = true
    data.configureAudioSession = true
    data.audioSessionMode = "voiceChat"
    data.isShowMissedCallNotification = false // the API sends its own "Missed call"
    data.extra = ["from": (p["from"] as? String) ?? "", "video": video] as NSDictionary
    callkit.showCallkitIncoming(data, fromPushKit: true, completion: { completion() })
  }

  /// A "call_cancel" VoIP push. iOS requires every VoIP push to be reported to CallKit, so it is reported like a call
  /// and ended at once: when the call is already on screen, reporting the same id is refused (nothing flashes) and
  /// the call is ended; when the app was not running, the report puts the call up for an instant and it is ended.
  /// A call answered on this phone is left alone (a throwaway id is reported instead).
  private func cancelCall(_ callkit: SwiftFlutterCallkitIncomingPlugin, callId: String, completion: @escaping () -> Void) {
    let id = callId.lowercased()
    let live = CXCallObserver().calls.first { $0.uuid.uuidString.lowercased() == id }
    let busy = answered.contains(id) || (live?.hasConnected ?? false)
    let reportId = busy || UUID(uuidString: callId) == nil ? UUID().uuidString : callId
    let data = flutter_callkit_incoming.Data(id: reportId, nameCaller: "WEBWEB AI", handle: "WEBWEB AI", type: 0)
    data.appName = "WEBWEB AI"
    data.isShowMissedCallNotification = false
    data.includesCallsInRecents = false
    callkit.showCallkitIncoming(data, fromPushKit: true, completion: { [weak self] in
      if let uuid = UUID(uuidString: reportId) {
        self?.cancelling.insert(reportId.lowercased())
        CXCallController().request(CXTransaction(action: CXEndCallAction(call: uuid))) { _ in
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.cancelling.remove(reportId.lowercased()) }
        }
      }
      completion()
    })
  }

  // MARK: CallKit actions

  /// Declined on the iPhone's call screen. The caller is told from here, not only from Dart: when the app was closed
  /// or asleep, Dart may not be listening yet and its socket is down, and the caller kept ringing. Dart sends the same
  /// decline too when it can (call_manager.dart); the API takes whichever comes first.
  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    // ended by a cancel push (the caller hung up, another phone took it): nothing to tell the server
    if !cancelling.contains(call.data.uuid.lowercased()) { declineOnServer(call.data.uuid) }
    action.fulfill()
  }

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    answered.insert(call.data.uuid.lowercased())
    action.fulfill()
  }
  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    answered.remove(call.data.uuid.lowercased())
    action.fulfill()
  }
  func onTimeOut(_ call: Call) {}
  func didActivateAudioSession(_ audioSession: AVAudioSession) {}
  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}
  func providerDidReset() {}

  /// POST /app/calls/:id/decline with the member's token (both saved by Dart in shared_preferences: auth_provider.dart).
  /// The device id lets the server leave this phone out of the cancel it sends the member's other phones. A
  /// background task keeps the app running until the request is through (iOS suspends it right after the action),
  /// and one failed attempt (a network that is still waking up) is retried.
  private func declineOnServer(_ callId: String, attempt: Int = 0, task: UIBackgroundTaskIdentifier? = nil) {
    var bg = task ?? UIBackgroundTaskIdentifier.invalid
    if task == nil {
      bg = UIApplication.shared.beginBackgroundTask(withName: "call-decline") {
        UIApplication.shared.endBackgroundTask(bg)
        bg = .invalid
      }
    }
    func finish() {
      DispatchQueue.main.async {
        if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
        bg = .invalid
      }
    }
    let saved = UserDefaults.standard
    guard let api = saved.string(forKey: "flutter.apiUrl"), let token = saved.string(forKey: "flutter.token"),
          let id = callId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
          let url = URL(string: "\(api)/app/calls/\(id)/decline") else { return finish() }
    var req = URLRequest(url: url, timeoutInterval: 10)
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = [:]
    if let device = saved.string(forKey: "flutter.device_id") { body["deviceId"] = device }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req) { _, resp, err in
      let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
      // 404 is "the call has ended already": fine
      if (err != nil || code >= 500) && attempt < 2 {
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { self.declineOnServer(callId, attempt: attempt + 1, task: bg) }
      } else {
        finish()
      }
    }.resume()
  }
}
