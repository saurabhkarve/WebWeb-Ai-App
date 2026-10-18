import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  private var voipRegistry: PKPushRegistry?

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
}
