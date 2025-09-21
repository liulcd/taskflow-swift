// The Swift Programming Language
// https://docs.swift.org/swift-book

// TaskFlowObserver.swift
//
// Extension for TaskFlow to support observer pattern for value changes.
// Allows registering observer tasks that react to property changes asynchronously.
//
// Author: liulcd
//
// Usage:
//   - Add observer tasks to TaskFlow instances for keyPath changes.
//   - Notify observers with value updates.
//   - See README.md for usage examples.

import Foundation

public extension TaskFlow {
    /// Add an observer task for a given keyPath. The observer will be notified asynchronously when the value changes.
    /// - Parameters:
    ///   - observer: The observing object (used for lifecycle management).
    ///   - keyPath: The keyPath to observe.
    ///   - updated: Closure called with new and old values when the value changes.
    ///   - initial: If true, the observer is notified immediately with the current value.
    /// - Returns: The created observer TaskFlow.
    func addObserverTask(_ observer: AnyObject, keyPath: String, updated: @escaping (_ value: Any?, _ oldValue: Any?) -> Void, initial: Bool = false) async -> TaskFlow {
        var observerTasks = await getObserverTasks()
        var observerTask = observerTasks[keyPath]
        synchronized {
            if observerTask == nil {
                observerTask = TaskFlow(count: UInt.max)
                observerTasks[keyPath] = observerTask
            }
        }
        await setProperty(observerTasks, key: keyPath)
        let id = UUID().uuidString
        let task = TaskFlow({ [weak self, weak observer] finish in
            guard let _ = observer else {
                finish(nil)
                observerTask?.remove(id)
                return
            }
            guard let self = self else { return }
            self.handleObserverUpdated(updated)
            finish(nil)
        }, id: id, count: UInt.max)
        await task.setProperty(keyPath, key: task.getObserverKeyPathKey())
        await observerTask?.queue([task])
        if initial == true {
            handleObserverUpdated(updated)
        }
        return task
    }
    
    /// Remove a specific observer task asynchronously.
    /// - Parameter task: The observer TaskFlow to remove.
    func removeObserverTask(_ task: TaskFlow) async {
        let observerTasks = await getObserverTasks()
        let observerTask = observerTasks[task.getObserverKeyPathKey()]
        await observerTask?.remove(task.id)
    }
    
    /// Remove a specific observer task (convenience sync version).
    /// - Parameter task: The observer TaskFlow to remove.
    func removeObserverTask(_ task: TaskFlow) {
        Task {
            await removeObserverTask(task)
        }
    }
    
    /// Notify all observer tasks for the given keyPath of a value update.
    /// - Parameters:
    ///   - keyPath: The keyPath whose value changed.
    ///   - value: The new value to set and notify observers about.
    func updateObservedValue(_ keyPath: String, value: Any?) async {
        let key = getObserverValueKey()
        let oldValue = await getProperty(key)
        await setProperty(oldValue, key: getObserverOldValueKey())
        await setProperty(value, key: key)
        guard let observerTask = await getObserverTasks()[keyPath] else { return }
        await observerTask.flow()
    }
    
    /// Internal: Call the observer's update closure with the current and previous values.
    /// Internal: Call the observer's update closure with the current and previous values.
    /// - Parameter updated: The closure to call with new and old values.
    private func handleObserverUpdated(_ updated: @escaping (_ value: Any?, _ oldValue: Any?) -> Void) {
        guard let updated = SendableValue(value: updated).value as? (_ value: Any?, _ oldValue: Any?) -> Void else {
            return
        }
        Task {
            let value = await getProperty(getObserverValueKey())
            let oldValue = await getProperty(getObserverValueKey())
            updated(value, oldValue)
        }
    }
    
    /// Internal: Get or create the dictionary of observer tasks for this TaskFlow.
    private func getObserverTasks() async -> [String: TaskFlow] {
        let key = getObserverTasksKey()
        guard let tasks = await getProperty(key) as? [String: TaskFlow] else {
            let tasks: [String: TaskFlow] = [:]
            await setProperty(tasks, key: key)
            return tasks
        }
        return tasks
    }
        
    /// Internal: Key for storing observer tasks in properties.
    private func getObserverTasksKey() -> String {
        return "\(self.id)_observerTasks"
    }
    
    /// Internal: Key for storing the current observed value.
    private func getObserverValueKey() -> String {
        return "\(self.id)_observerValue"
    }
    
    /// Internal: Key for storing the previous observed value.
    private func getObserverOldValueKey() -> String {
        return "\(self.id)_observerOldValue"
    }
    
    /// Internal: Key for storing the keyPath associated with an observer task.
    private func getObserverKeyPathKey() -> String {
        return "\(self.id)_observerKeyPath"
    }
}


