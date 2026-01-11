import Foundation
import UIKit
import BackgroundTasks
import UserNotifications

/// Background Task Manager for iOS
/// Handles background fetch and processing for mesh SOS
class BackgroundTaskManager {
    
    static let shared = BackgroundTaskManager()
    
    // Task identifiers
    static let refreshTaskId = "com.development.anchormesh.mesh.refresh"
    static let processingTaskId = "com.development.anchormesh.mesh.processing"
    
    // USGS API
    static let usgsAPI = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/significant_hour.geojson"
    
    private init() {}
    
    /// Register background tasks with iOS
    func registerTasks() {
        // Register refresh task (runs every 5 min when possible)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskManager.refreshTaskId,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleRefreshTask(refreshTask)
        }

        // Register processing task (for longer operations)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskManager.processingTaskId,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleProcessingTask(processingTask)
        }
    }
    
    /// Schedule the next background fetch
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskManager.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes (iOS minimum for reliable scheduling)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled")
        } catch {
            print("Failed to schedule refresh: \(error)")
        }
    }
    
    /// Handle background refresh task
    private func handleRefreshTask(_ task: BGAppRefreshTask) {
        // Schedule next refresh
        scheduleRefresh()
        
        // Create operation
        let queue = OperationQueue()
        let operation = DisasterCheckOperation()
        
        // Handle expiration
        task.expirationHandler = {
            queue.cancelAllOperations()
        }
        
        // Complete when done
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        queue.addOperation(operation)
    }
    
    /// Handle processing task (longer background work)
    private func handleProcessingTask(_ task: BGProcessingTask) {
        let queue = OperationQueue()
        let operation = MeshSyncOperation()
        
        task.expirationHandler = {
            queue.cancelAllOperations()
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        queue.addOperation(operation)
    }
    
    /// Check for disasters (USGS)
    func checkForDisasters() async -> Bool {
        guard let url = URL(string: BackgroundTaskManager.usgsAPI) else { return false }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = String(data: data, encoding: .utf8) ?? ""
            return json.contains("\"mag\":")
        } catch {
            return false
        }
    }
    
    /// Ping Google to check internet
    func checkInternet() async -> Bool {
        guard let url = URL(string: "https://www.google.com") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        
        return false
    }
    
    /// Set disaster alert flag
    func setAlertFlag(_ alert: Bool) {
        UserDefaults.standard.set(alert, forKey: "disaster_alert")
    }
}

/// Operation for checking disasters
class DisasterCheckOperation: Operation {
    override func main() {
        guard !isCancelled else { return }
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            let hasDisaster = await BackgroundTaskManager.shared.checkForDisasters()
            let hasInternet = await BackgroundTaskManager.shared.checkInternet()
            
            if hasDisaster || !hasInternet {
                BackgroundTaskManager.shared.setAlertFlag(true)
                // Send local notification
                self.sendNotification(hasDisaster: hasDisaster)
            } else {
                BackgroundTaskManager.shared.setAlertFlag(false)
            }
            
            semaphore.signal()
        }
        
        semaphore.wait()
    }
    
    private func sendNotification(hasDisaster: Bool) {
        let content = UNMutableNotificationContent()
        content.title = hasDisaster ? "⚠️ Disaster Alert" : "📡 Mesh Mode"
        content.body = hasDisaster 
            ? "Earthquake detected. AnchorMesh activated."
            : "Internet unavailable. Mesh mode recommended."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

/// Operation for syncing mesh data
class MeshSyncOperation: Operation {
    override func main() {
        guard !isCancelled else { return }
        
        // TODO: Sync stored SOS packets to cloud when internet available
        print("Mesh sync operation running")
    }
}
