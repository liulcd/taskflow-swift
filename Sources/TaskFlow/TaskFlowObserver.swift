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
import SendableValue

public extension TaskFlow {
    /// Synchronously notify all observer tasks for the given keyPath of a value update.
    /// Add an observer task for a given keyPath. The observer will be notified asynchronously when the value changes.
    /// - Parameters:
    ///   - observer: The observing object (used for lifecycle management).
    ///   - keyPath: The keyPath to observe.
    ///   - updated: Closure called with new and old values when the value changes.
    ///   - initial: If true, the observer is notified immediately with the current value.
    /// - Returns: The created observer TaskFlow.
    @discardableResult
    func addObserverTask(_ observer: AnyObject, keyPath: String, updated: @escaping (_ value: Any?, _ oldValue: Any?) -> Void, initial: Bool = false) -> TaskFlow {
        var observerTasks = getObserverTasks()
        var observerTask = observerTasks[keyPath]
        synchronized {
            if observerTask == nil {
                observerTask = TaskFlow(count: UInt.max)
                observerTasks[keyPath] = observerTask
            }
        }
        properties[observerTasksKey] = observerTasks
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
        task.properties[task.observerKeyPathKey] = keyPath
        let updated = SendableUpdatedHandlerValue(updated)
        let tasks = SendableValue([task])
        let observer = SendableValue(observerTask)
        Task {
            guard let tasks = tasks.value as? [TaskFlow], let observerTask = observer.value as? TaskFlow else {
                return
            }
            await observerTask.queue(tasks)
            if initial == true {
                handleObserverUpdated(updated.value)
            }
        }
        return task
    }
    
    /// Remove a specific observer task asynchronously.
    /// - Parameter task: The observer TaskFlow to remove.
    func removeObserverTask(_ task: TaskFlow) async {
        let observerTasks = getObserverTasks()
        let observerTask = observerTasks[task.observerKeyPathKey]
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
        let oldValue = properties[observerValueKey]
        properties[observerOldValueKey] = oldValue
        properties[observerValueKey] = value
        guard let observerTask = getObserverTasks()[keyPath] else { return }
        await observerTask.flow()
    }
    
    /// Notify all observer tasks for the given keyPath of a value update.
    /// - Parameters:
    ///   - keyPath: The keyPath whose value changed.
    ///   - value: The new value to set and notify observers about.
    func updateObservedValue(_ keyPath: String, value: Any?) {
        let value = SendableValue(value)
        Task {
            await updateObservedValue(keyPath, value: value.value)
        }
    }
    
    /// Internal: Call the observer's update closure with the current and previous values.
    /// Internal: Call the observer's update closure with the current and previous values.
    /// - Parameter updated: The closure to call with new and old values.
    private func handleObserverUpdated(_ updated: (_ value: Any?, _ oldValue: Any?) -> Void) {
        let value = properties[observerValueKey]
        let oldValue = properties[observerOldValueKey]
        updated(value, oldValue)
    }
    
    /// Internal: Get or create the dictionary of observer tasks for this TaskFlow.
    private func getObserverTasks() -> [String: TaskFlow] {
        guard let tasks = properties[observerTasksKey] as? [String: TaskFlow] else {
            let tasks: [String: TaskFlow] = [:]
            properties[observerTasksKey] = tasks
            return tasks
        }
        return tasks
    }
        
    /// The property key used to store the observer tasks dictionary.
    private var observerTasksKey: String {
        get {
            return "\(self.id)_observerTasks"
        }
    }
    
    /// The property key used to store the current observed value.
    private var observerValueKey: String {
        get {
            return "\(self.id)_observerValue"
        }
    }
    
    /// The property key used to store the previous observed value.
    private var observerOldValueKey: String {
        get {
            return "\(self.id)_observerOldValue"
        }
    }
    
    /// The property key used to store the keyPath associated with an observer task.
    private var observerKeyPathKey: String {
        get {
            return "\(self.id)_observerKeyPath"
        }
    }
}


