// The Swift Programming Language
// https://docs.swift.org/swift-book

// TaskFlow: A lightweight Swift library for managing asynchronous task flows with dependencies.
// https://github.com/liulcd/taskflow-swift
//
// Author: liulcd
//
// This file defines the core TaskFlow class and supporting types for orchestrating dependent asynchronous tasks.
//
// Usage:
//   - Define tasks and their dependencies.
//   - Use TaskFlow to queue and execute tasks in order, handling errors and completion.
//
// See README.md for more details and examples.

import Foundation

internal class SendableValue: NSObject, @unchecked Sendable {
    let value: Any?
    
    init(value: Any?) {
        self.value = value
    }
}

/// Helper class to wrap AnyHashable for Sendable conformance.
internal class SendableHash: NSObject, @unchecked Sendable {
    let value: AnyHashable

    init(value: AnyHashable) {
        self.value = value
    }
}

/// An actor that manages the queue and execution state of TaskFlow tasks.
private actor TaskFlowActor: @unchecked Sendable {
    /// 2D array of task groups, each group can be executed in parallel.
    private(set) var tasks: [[TaskFlow]] = []

    /// Track all queued task IDs to prevent duplicates.
    private var taskIds: [AnyHashable] = []

    /// Queue a set of tasks, resolving dependencies and removing duplicates.
    func queue(tasks: [TaskFlow]) {
        let allTasks = getAllTasks(tasks)
        allTasks.forEach { elements in
            var elements = elements
            elements.removeAll { element in
                return taskIds.contains { elementId in
                    return element.id == elementId
                }
            }
            if elements.count > 0 {
                elements.forEach { element in
                    self.taskIds.append(element.id)
                }
                self.tasks.append(elements)
            }
        }
    }
    
    /// Recursively resolve all dependencies for the given tasks.
    private func getAllTasks(_ tasks: [TaskFlow]) -> [[TaskFlow]] {
        let tasks = removeDuplicateTasks(tasks)
        var allTasks: [[TaskFlow]] = []
        tasks.forEach { element in
            guard let depends = element.depends else { return }
            if depends.count > 0 {
                var dependTasks = self.getAllTasks(depends)
                if dependTasks.count > 0 {
                    dependTasks.reverse()
                    for index in 0 ..< dependTasks.count {
                        if allTasks.count <= index {
                            allTasks.append([])
                        }
                        allTasks[index].append(contentsOf: dependTasks[index])
                    }
                }
            }
        }
        allTasks.reverse()
        allTasks.append(tasks)
        return allTasks
    }
    
    /// Remove duplicate tasks by their IDs.
    private func removeDuplicateTasks(_ tasks: [TaskFlow]) -> [TaskFlow] {
        var taskIds: [AnyHashable] = []
        var results: [TaskFlow] = []
        tasks.forEach { element in
            if !taskIds.contains(where: { elementId in
                return elementId == element.id
            }) {
                taskIds.append(element.id)
                results.append(element)
            }
        }
        return results
    }
    
    /// Remove a task by its ID from the queue.
    func remove(_ id: AnyHashable) {
        for index in 0 ..< tasks.count {
            tasks[index].removeAll { element in
                return element.id == id
            }
        }
        taskIds.removeAll { elementId in
            return elementId == id
        }
        tasks.removeAll { elements in
            elements.count == 0
        }
    }
    
    /// Clear all tasks and IDs from the queue.
    func clear() {
        tasks.removeAll()
        taskIds.removeAll()
    }
    
    private var properties: [AnyHashable: Any] = [:]
    
    func setProperty(_ property: Any?, key: AnyHashable) {
        properties[key] = properties
    }
    
    func getProperty(_ key: AnyHashable) -> SendableValue? {
        return SendableValue(value: properties[key])
    }
}

/// The handler type for a TaskFlow. Call `finish(nil)` on success, or `finish(error)` on failure.
public typealias TaskFlowHandler = (_ finish: (_ error: NSError?) -> Void) -> Void

/// TaskFlow: Represents a single asynchronous task with optional dependencies.
/// Supports chaining, error handling, and repeat count.
public class TaskFlow: NSObject, @unchecked Sendable {
    private let actor = TaskFlowActor()
    
    /// Unique identifier for the task.
    let id: AnyHashable

    /// The closure to execute for this task.
    let flowHandler: TaskFlowHandler?

    /// Optional dependencies. These tasks must complete before this one starts.
    let depends: [TaskFlow]?

    /// Number of times to repeat this task before finishing.
    private var count: UInt = 1

    /// Initialize a TaskFlow.
    /// - Parameters:
    ///   - flowHandler: The closure to execute for this task.
    ///   - id: Unique identifier (default: random UUID string).
    ///   - count: Number of times to repeat (default: 1).
    ///   - depends: Array of dependent TaskFlow objects.
    public init(_ flowHandler: TaskFlowHandler? = nil, id: AnyHashable = UUID.init().uuidString, count: UInt = 1, depends: [TaskFlow]? = nil) {
        self.flowHandler = flowHandler
        self.id = id
        self.count = count
        self.depends = depends
    }
    
    /// Indicates if the task is currently running.
    private var isFlowing: Bool = false

    /// Indicates if the task has finished.
    private var isFinished: Bool = false {
        didSet {
            if isFinished == true {
                isFlowing = false
            }
        }
    }

    /// Optional error handler for task failures.
    private var failHandler: ((_ task: TaskFlow, _ error: Error) -> Void)?
}

// MARK: - TaskFlow Execution
public extension TaskFlow {
     /// Queue tasks for execution. Set `clear` to true to remove previous tasks. Dependencies are handled automatically.
    func queue(_ tasks: [TaskFlow], clear: Bool = false) async {
        if clear == true {
            await self.actor.clear()
        }
        if self.flowHandler != nil {
            if await self.actor.tasks.count == 0 {
                await self.actor.queue(tasks: [self])
            }
        }
        await self.actor.queue(tasks: tasks)
    }
    
    /// Start executing the queued tasks, with optional error handler.
    func flow(_ failHandler: ((_ task: TaskFlow, _ error: Error) -> Void)? = nil) async {
        if self.flowHandler != nil {
            if await self.actor.tasks.count == 0 {
                await self.actor.queue(tasks: [self])
            }
        }
        let tasks = await self.actor.tasks
        guard let next = self.getNextTasks(tasks) else {
            return
        }
        self.synchronized {
            self.failHandler = failHandler
            self.flow(tasks, current: next)
        }
    }
    
    /// Internal: Execute the current group of tasks in parallel.
    private func flow(_ tasks: [[TaskFlow]], current: [TaskFlow]) {
        current.forEach { element in
            if element.count > 0 && element.flowHandler != nil {
                if element.isFlowing == true {
                    return
                }
                element.isFinished = false
                element.flowHandler?{ [weak self] error in
                    guard let self = self else { return }
                    self.synchronized {
                        if let error = error {
                            element.isFlowing = false
                            self.failHandler?(element, error)
                            return
                        }
                        element.count -= 1
                        if element.count == 0 {
                            self.remove(element.id)
                        }
                        element.isFinished = true
                        self.flowNext(tasks, current: current)
                    }
                }
            } else if element.count == 0 {
                self.remove(element.id)
                flowNext(tasks, current: current)
            } else {
                element.isFinished = true
                flowNext(tasks, current: current)
            }
        }
    }
    
    /// Internal: Proceed to the next group of tasks if all in the current group are finished.
    private func flowNext(_ tasks: [[TaskFlow]], current: [TaskFlow]) {
        var finished = true
        current.forEach { element in
            if element.isFinished == false {
                finished = false
            }
        }
        if finished {
            guard let next = self.getNextTasks(tasks, current: current) else {
                return
            }
            self.flow(tasks, current: next)
        }
    }
    
    /// Internal: Get the next group of tasks to execute.
    private func getNextTasks(_ tasks: [[TaskFlow]], current: [TaskFlow]? = nil) -> [TaskFlow]? {
        var next: [TaskFlow]?
        if tasks.count > 0 {
            guard let current = current else {
                next = tasks.first
                if next?.count ?? 0 == 0  {
                    return getNextTasks(tasks, current: next)
                }
                return next
            }
            guard let index = tasks.firstIndex(of: current) else {
                return next
            }
            if tasks.count > index {
                next = tasks[index + 1]
                if next?.count ?? 0 == 0  {
                    return getNextTasks(tasks, current: next)
                }
            }
        }
        return next
    }
    
    /// Remove a task by its ID asynchronously.
    func remove(_ id: AnyHashable) async {
        let hash = SendableHash(value: id)
        await self.actor.remove(hash.value)
    }
    
    func remove(_ id: AnyHashable) {
        let hash = SendableHash(value: id)
        Task {
            await self.actor.remove(hash.value)
        }
    }
    
    /// Clear all tasks asynchronously.
    func clear() async {
        await self.actor.clear()
    }
    
    func getProperty(_ key: AnyHashable) async -> Any? {
        let hash = SendableHash(value: key)
        return await self.actor.getProperty(hash.value)?.value
    }
    
    func setProperty(_ property: Any?, key: AnyHashable) async {
        let hash = SendableHash(value: key)
        let property = SendableValue(value: property)
        await self.actor.setProperty(property.value, key: hash.value)
    }
}

// MARK: - Main TaskFlow Singleton
extension TaskFlow {
    /// Shared main TaskFlow instance.
    static let main = TaskFlow()
}

// MARK: - NSObject Extension for TaskFlow Association
public extension NSObject {
    private struct TaskFlowAssociatedKey {
        nonisolated(unsafe) static var taskFlow: Void?
    }
    
    /// Associated TaskFlow instance for any NSObject.
    var taskFlow: TaskFlow {
        get {
            return synchronized {
                guard let taskFlow = objc_getAssociatedObject(self, &TaskFlowAssociatedKey.taskFlow) as? TaskFlow else {
                    let taskFlow = TaskFlow()
                    objc_setAssociatedObject(self, &TaskFlowAssociatedKey.taskFlow, taskFlow, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    return taskFlow
                }
                return taskFlow
            }
        }
        set {
            synchronized {
                objc_setAssociatedObject(self, &TaskFlowAssociatedKey.taskFlow, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
}

// MARK: - NSObject Synchronization Helper
internal extension NSObject {
    @discardableResult
    /// Thread-safe execution of a closure using objc_sync.
    func synchronized<T>(_ closure: () -> T) -> T {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        return closure()
    }
}
