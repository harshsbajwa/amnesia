//
//  AppDelegate.swift
//  amnesia
//

import SwiftUI
import Combine

struct CaptureEventDisplayItem: Identifiable {
    let id: UUID
    let timestamp: String
    let applicationName: String
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var chatWindow: NSWindow?
    var popover: NSPopover?

    var chatViewModel: ChatViewModel!
    var screenCaptureService: ScreenCaptureService!
    var ocrService: OCRService!
    var dataStorageService: DataStorageService!
    var permissionsManager: PermissionsManager!

    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        print("[AppDelegate] AppDelegate init completed.")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching started.")
        ocrService = OCRService()
        dataStorageService = DataStorageService()
        screenCaptureService = ScreenCaptureService(ocrService: ocrService, dataStorageService: dataStorageService)
        permissionsManager = PermissionsManager() // Initial checkScreenRecordingPermission happens in its init
        chatViewModel = ChatViewModel(mlxService: MLXService(), dataStorageService: dataStorageService)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Amnesia Paused")
            print("[AppDelegate] StatusItem button created successfully.")
          
          

            let popoverView = MenuBarPopoverView(
                chatViewModel: self.chatViewModel,
                screenCaptureService: self.screenCaptureService,
                permissionsManager: self.permissionsManager,
                dataStorageService: self.dataStorageService,
                openChatWindowAction: { [weak self] in self?.openChatWindow() },
                toggleCaptureAction: { [weak self] in
                    print("[AppDelegate] toggleCaptureAction closure called from Popover.")
                    self?.toggleGlobalCaptureAction()
                },
                quitAction: { NSApp.terminate(nil) }
            )

            self.popover = NSPopover()
            self.popover?.contentSize = NSSize(width: 350, height: 420)
            self.popover?.behavior = .transient
            self.popover?.contentViewController = NSHostingController(rootView: popoverView)

            button.action = #selector(togglePopover(_:))
            button.target = self
            print("[AppDelegate] Popover setup complete. Popover is nil: \(self.popover == nil)")
        } else {
            print("[AppDelegate] Error: StatusItem button could not be created.")
        }

        screenCaptureService.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCapturing in
                self?.statusItem?.button?.image = NSImage(systemSymbolName: isCapturing ? "eye" : "eye.slash",
                                                          accessibilityDescription: isCapturing ? "Amnesia Capturing" : "Amnesia Paused")
            }
            .store(in: &cancellables)

        // permissionsManager.checkScreenRecordingPermission() // Already called in PermissionsManager.init()
        openChatWindow()
        print("[AppDelegate] applicationDidFinishLaunching finished.")
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            print("[AppDelegate] togglePopover: StatusItem button is nil. Cannot proceed.")
            return
        }
        print("[AppDelegate] togglePopover called. Sender: \(String(describing: sender)).")

        guard let strongPopover = self.popover else {
            print("[AppDelegate] togglePopover: self.popover is nil. Cannot proceed.")
            return
        }

        if strongPopover.isShown {
            strongPopover.performClose(sender)
            print("[AppDelegate] Popover closed via performClose.")
        } else {
            print("[AppDelegate] Attempting to show popover...")
            permissionsManager.updateAuthorizationStatus() // Refresh permission status before showing

            strongPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            // Ensure the popover's window becomes key to accept events and for correct appearance.
            // This needs to happen *after* show has been called and the window exists.
            // A slight delay might sometimes be necessary if the window isn't immediately available.
            DispatchQueue.main.async { // Defer slightly to ensure window is set up
                if strongPopover.isShown { // Check again in case it was closed quickly
                     strongPopover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                     print("[AppDelegate] Popover shown and made key and front.")
                } else {
                     print("[AppDelegate] Popover was not shown or closed before makeKey attempt.")
                }
            }
            NotificationCenter.default.post(name: .popoverDidShow, object: nil) // Notify that an attempt to show was made
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        print("[AppDelegate] applicationDidBecomeActive.")
        permissionsManager.updateAuthorizationStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openChatWindow()
        } else {
            chatWindow?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func openChatWindow() {
        if let strongPopover = self.popover, strongPopover.isShown {
            strongPopover.performClose(nil)
            print("[AppDelegate] Closed popover before opening chat window.")
        }

        if chatWindow == nil || !chatWindow!.isVisible {
            guard let chatViewModel = self.chatViewModel, let dataStorageService = self.dataStorageService else {
                print("[AppDelegate] Critical error: chatViewModel or dataStorageService not initialized when opening chat window.")
                return
            }
            let chatView = ChatView(viewModel: chatViewModel, dataStorageService: dataStorageService)

            if chatWindow == nil {
                chatWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 800, height: 950),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                    backing: .buffered, defer: false)
                chatWindow?.center()
                chatWindow?.setFrameAutosaveName("AmnesiaChatWindow")
                chatWindow?.isReleasedWhenClosed = false
                chatWindow?.title = "Amnesia Chat"
            }
            chatWindow?.contentView = NSHostingView(rootView: chatView.environmentObject(self))
             print("[AppDelegate] Chat window configured/created.")
        }
        chatWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) // Ensure app is active when chat window is brought forward
        print("[AppDelegate] Chat window made key and order front.")
    }

    func increaseCaptureFrequency() {
        let currentInterval = screenCaptureService.captureInterval
        let newInterval = max(1.0, currentInterval / 2.0)
        screenCaptureService.captureInterval = newInterval
        UserDefaults.standard.set(newInterval, forKey: UserDefaultsKeys.captureInterval)
        print("[AppDelegate] Capture interval decreased to: \(newInterval)s")
    }

    func decreaseCaptureFrequency() {
        let currentInterval = screenCaptureService.captureInterval
        let newInterval = min(300.0, currentInterval * 2.0)
        screenCaptureService.captureInterval = newInterval
        UserDefaults.standard.set(newInterval, forKey: UserDefaultsKeys.captureInterval)
        print("[AppDelegate] Capture interval increased to: \(newInterval)s")
    }
    
    func setCaptureInterval(_ interval: TimeInterval) {
        let newInterval = max(1.0, min(300.0, interval))
        screenCaptureService.captureInterval = newInterval // ScreenCaptureService.didSet handles timer reset if capturing
        UserDefaults.standard.set(newInterval, forKey: UserDefaultsKeys.captureInterval)
        print("[AppDelegate] Capture interval set to: \(newInterval)s via setCaptureInterval.")
    }

    func toggleGlobalCaptureAction() {
      // Log entry to the function itself
      print("[AppDelegate] toggleGlobalCaptureAction: ENTRY. Current capture state (screenCaptureService.isCapturing) before Task: \(screenCaptureService.isCapturing)")
      
      Task { // This Task is on the MainActor because AppDelegate is @MainActor
          print("[AppDelegate] toggleGlobalCaptureAction: TASK STARTED. isCancelled: \(Task.isCancelled)")
          print("[AppDelegate] toggleGlobalCaptureAction: Current capture state (screenCaptureService.isCapturing) *inside* Task: \(screenCaptureService.isCapturing)")
          
          if Task.isCancelled {
              print("[AppDelegate] toggleGlobalCaptureAction: Task was cancelled before logic execution.")
              return
          }

          if screenCaptureService.isCapturing {
              print("[AppDelegate] toggleGlobalCaptureAction: Task sees isCapturing = TRUE. Attempting to stop.")
              await screenCaptureService.stopCapturing()
              print("[AppDelegate] toggleGlobalCaptureAction: screenCaptureService.stopCapturing() has RETURNED.")
          } else {
              print("[AppDelegate] toggleGlobalCaptureAction: Task sees isCapturing = FALSE. Attempting to start.")
              print("[AppDelegate] toggleGlobalCaptureAction: Checking permissionsManager.isScreenRecordingAuthorized: \(permissionsManager.isScreenRecordingAuthorized)")
              
              if permissionsManager.isScreenRecordingAuthorized {
                  print("[AppDelegate] toggleGlobalCaptureAction: Permissions AUTHORIZED. Calling screenCaptureService.startCapturing().")
                  await screenCaptureService.startCapturing()
                  print("[AppDelegate] toggleGlobalCaptureAction: screenCaptureService.startCapturing() has RETURNED. New capture state: \(screenCaptureService.isCapturing)")
              } else {
                  print("[AppDelegate] toggleGlobalCaptureAction: Permissions NOT AUTHORIZED. Requesting and showing alert.")
                  permissionsManager.requestScreenRecordingPermission()
                  let alert = NSAlert()
                  alert.messageText = "Screen Recording Permission Required"
                  alert.informativeText = "Amnesia needs screen recording permission to function. Please enable it in System Settings > Privacy & Security > Screen Recording, then try starting capture again."
                  alert.addButton(withTitle: "Open Settings")
                  alert.addButton(withTitle: "Cancel")
                  if alert.runModal() == .alertFirstButtonReturn {
                      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                          NSWorkspace.shared.open(url)
                      }
                  }
              }
          }
          print("[AppDelegate] toggleGlobalCaptureAction: TASK FINISHED. isCancelled: \(Task.isCancelled)")
      }
      print("[AppDelegate] toggleGlobalCaptureAction: EXIT (Task launched).")
  }
}

extension NSNotification.Name {
    static let popoverDidShow = NSNotification.Name("popoverDidShowNotification")
}

struct UserDefaultsKeys {
    static let captureInterval = "captureInterval"
    static let ocrRecognitionLevel = "ocrRecognitionLevel"
    static let excludedAppBundleIDs = "excludedAppBundleIDs"
    static let excludedWindowTitleKeywords = "excludedWindowTitleKeywords"
    static let ignoreIncognitoWindows = "ignoreIncognitoWindows"
}

struct MenuBarPopoverView: View {
    var chatViewModel: ChatViewModel
    @ObservedObject var screenCaptureService: ScreenCaptureService
    @ObservedObject var permissionsManager: PermissionsManager
    var dataStorageService: DataStorageService

    var openChatWindowAction: () -> Void
    var toggleCaptureAction: () -> Void
    var quitAction: () -> Void

    @State private var recentCaptures: [CaptureEventDisplayItem] = []
    private let dateFormatter: DateFormatter
    @State private var refreshTimer: Timer?
    @State private var isPopoverVisible: Bool = false
    @State private var localCaptureInterval: Double

    init(chatViewModel: ChatViewModel,
         screenCaptureService: ScreenCaptureService,
         permissionsManager: PermissionsManager,
         dataStorageService: DataStorageService,
         openChatWindowAction: @escaping () -> Void,
         toggleCaptureAction: @escaping () -> Void,
         quitAction: @escaping () -> Void) {
        self.chatViewModel = chatViewModel
        self.screenCaptureService = screenCaptureService
        self.permissionsManager = permissionsManager
        self.dataStorageService = dataStorageService
        self.openChatWindowAction = openChatWindowAction
        self.toggleCaptureAction = toggleCaptureAction
        self.quitAction = quitAction

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "MMM d, HH:mm:ss"
        
        _localCaptureInterval = State(initialValue: screenCaptureService.captureInterval)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Amnesia")
                .font(.title2)
                .padding(.bottom, 3)

            if !permissionsManager.isScreenRecordingAuthorized {
                VStack(spacing: 4) {
                    Text("Screen Recording permission is required.")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Grant Permission") {
                        permissionsManager.requestScreenRecordingPermission()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Button {
                print("[MenuBarPopoverView] 'Start/Pause Capturing' button tapped.")
                print("[MenuBarPopoverView] Current permission state (permissionsManager.isScreenRecordingAuthorized): \(permissionsManager.isScreenRecordingAuthorized)")
                print("[MenuBarPopoverView] Current capture state (screenCaptureService.isCapturing): \(screenCaptureService.isCapturing)")
                self.toggleCaptureAction()
            } label: {
                Label(screenCaptureService.isCapturing ? "Pause Capturing" : "Start Capturing",
                      systemImage: screenCaptureService.isCapturing ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!permissionsManager.isScreenRecordingAuthorized && !screenCaptureService.isCapturing)
            .controlSize(.regular)

            Button {
                openChatWindowAction()
                (NSApp.delegate as? AppDelegate)?.popover?.performClose(nil)
            } label: {
                Label("Open Chat Window", systemImage: "message.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Capture Interval: \(Int(localCaptureInterval))s")
                    .font(.caption)
                Slider(value: $localCaptureInterval, in: 5...120, step: 5) {
                    Text("Capture Interval")
                } minimumValueLabel: {
                    Text("5s").font(.caption2)
                } maximumValueLabel: {
                    Text("120s").font(.caption2)
                } onEditingChanged: { editingFinished in
                    if editingFinished {
                        print("[MenuBarPopoverView] Slider editing finished. New interval: \(localCaptureInterval)")
                        (NSApp.delegate as? AppDelegate)?.setCaptureInterval(localCaptureInterval)
                    }
                }
                Text("Changes apply when capture (re)starts.")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.top, 5)

            Divider().padding(.vertical, 2)

            if recentCaptures.isEmpty && !screenCaptureService.isCapturing {
                Text("No captures yet. Start capturing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
            } else if recentCaptures.isEmpty && screenCaptureService.isCapturing {
                 Text("Capturing... waiting for first event.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
            }else {
                List {
                    ForEach(recentCaptures) { item in
                        HStack {
                            Text(item.applicationName)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            Text(item.timestamp)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, -2)
                    }
                }
                .listStyle(.plain)
                .frame(height: 70)
            }

            Divider().padding(.vertical, 3)

            Button {
                quitAction()
            } label: {
                Label("Quit Amnesia", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .frame(minWidth: 300, idealWidth: 330)
        .onAppear {
            print("[MenuBarPopoverView] onAppear triggered. Current isPopoverVisible: \(isPopoverVisible)")
            if !isPopoverVisible { // Extra check to avoid redundant setup if already visible
                isPopoverVisible = true
                localCaptureInterval = screenCaptureService.captureInterval
                permissionsManager.updateAuthorizationStatus()
                startRefreshTimer()
                Task { await refreshRecentCaptures() }
            } else {
                // If already visible (e.g. re-layout without full disappear/appear), still refresh
                permissionsManager.updateAuthorizationStatus()
                Task { await refreshRecentCaptures() }
            }
        }
        .onDisappear {
            print("[MenuBarPopoverView] onDisappear triggered.")
            isPopoverVisible = false
            stopRefreshTimer()
        }
        .onChange(of: screenCaptureService.isCapturing) { _,_ in
             print("[MenuBarPopoverView] screenCaptureService.isCapturing changed. Refreshing recent captures.")
            Task {
                await refreshRecentCaptures()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidShow)) { _ in
            print("[MenuBarPopoverView] Received popoverDidShow notification. Current isPopoverVisible: \(isPopoverVisible)")
            // We can refresh data here as a safeguard or if onAppear logic is conditional.
            if !isPopoverVisible {
                 print("[MenuBarPopoverView] Popover was not marked as visible from onReceive, running minimal setup.")
                 isPopoverVisible = true // Align state
                 // Minimal necessary updates if onAppear didn't fully run or state is out of sync.
                 permissionsManager.updateAuthorizationStatus()
                 localCaptureInterval = screenCaptureService.captureInterval
                 startRefreshTimer() // Ensure timer is running
            }
            Task { await refreshRecentCaptures() } // Always good to refresh data on show
        }
        .onChange(of: screenCaptureService.captureInterval) { _, newValue in
            print("[MenuBarPopoverView] screenCaptureService.captureInterval changed externally to \(newValue). Updating local slider.")
            localCaptureInterval = newValue
        }
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil || !refreshTimer!.isValid else {
            print("[MenuBarPopoverView] Refresh timer already exists and is valid.")
            return
        }
        print("[MenuBarPopoverView] Starting refresh timer.")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            // print("[MenuBarPopoverView] Refresh timer fired.") // Can be noisy
            Task {
                await refreshRecentCaptures()
            }
        }
        // Initial refresh when timer starts
        Task { await refreshRecentCaptures() }
    }

    private func stopRefreshTimer() {
        if let timer = refreshTimer, timer.isValid {
            print("[MenuBarPopoverView] Stopping refresh timer.")
            timer.invalidate()
        }
        refreshTimer = nil
    }

    private func refreshRecentCaptures() async {
        let events = await dataStorageService.fetchRecentEvents(limit: 3)
        let newCaptureItems = events.map { eventData -> CaptureEventDisplayItem in
            CaptureEventDisplayItem(
                id: UUID(),
                timestamp: eventData.timestamp != nil ? dateFormatter.string(from: eventData.timestamp!) : "Unknown time",
                applicationName: eventData.applicationName ?? "Unknown App"
            )
        }

        let countsDiffer = self.recentCaptures.count != newCaptureItems.count
        var contentIsDifferent = false

        if !countsDiffer && !self.recentCaptures.isEmpty && !newCaptureItems.isEmpty {
            contentIsDifferent = !zip(self.recentCaptures, newCaptureItems).allSatisfy { oldItem, newItem in
                oldItem.timestamp == newItem.timestamp && oldItem.applicationName == newItem.applicationName
            }
        } else if countsDiffer {
            contentIsDifferent = true
        }

        if contentIsDifferent {
            self.recentCaptures = newCaptureItems
            // print("[MenuBarPopoverView] Refreshed recent captures. Count: \(self.recentCaptures.count)") // Can be noisy
        }
    }
}
