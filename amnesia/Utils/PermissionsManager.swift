//
//  PermissionsManager.swift
//  amnesia
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit
import Combine

@MainActor
class PermissionsManager: ObservableObject {
    @Published var isScreenRecordingAuthorized: Bool = false

    init() {
        checkScreenRecordingPermission()
    }

    func checkScreenRecordingPermission() {
        let currentStatus = CGPreflightScreenCaptureAccess()
        print("[PermissionsManager] checkScreenRecordingPermission: CGPreflightScreenCaptureAccess() returned \(currentStatus). Current @Published value: \(self.isScreenRecordingAuthorized)")
        if self.isScreenRecordingAuthorized != currentStatus {
            self.isScreenRecordingAuthorized = currentStatus
            print("[PermissionsManager] Updated isScreenRecordingAuthorized to \(currentStatus).")
        }
    }

    func requestScreenRecordingPermission() {
        let preflightStatus = CGPreflightScreenCaptureAccess()
        print("[PermissionsManager] requestScreenRecordingPermission: Pre-request CGPreflightScreenCaptureAccess() is \(preflightStatus).")
        if !preflightStatus {
            // CGRequestScreenCaptureAccess is synchronous and shows the dialog.
            // The user's choice is asynchronous.
            let grantedSynchronously = CGRequestScreenCaptureAccess()
            print("[PermissionsManager] Screen recording permission request initiated. Synchronous part of CGRequestScreenCaptureAccess() returned: \(grantedSynchronously)")
            // After this, the user interacts with the system dialog.
            // The app should re-check permission status when it becomes active or when the user tries the action again.
        } else {
            print("[PermissionsManager] Requesting permission, but CGPreflightScreenCaptureAccess is already true.")
            if !self.isScreenRecordingAuthorized {
                 self.isScreenRecordingAuthorized = true
                 print("[PermissionsManager] Updated isScreenRecordingAuthorized to true as preflight was already true.")
            }
        }
    }

    func updateAuthorizationStatus() {
        let previousStatus = isScreenRecordingAuthorized
        let currentCGStatus = CGPreflightScreenCaptureAccess()
        print("[PermissionsManager] updateAuthorizationStatus: CGPreflightScreenCaptureAccess() returned \(currentCGStatus). Previous @Published value: \(previousStatus)")
        if previousStatus != currentCGStatus {
            isScreenRecordingAuthorized = currentCGStatus
            print("[PermissionsManager] Screen recording permission status changed from \(previousStatus) to: \(isScreenRecordingAuthorized)")
        } else {
            print("[PermissionsManager] Screen recording permission status remains: \(isScreenRecordingAuthorized)")
        }
    }
}
