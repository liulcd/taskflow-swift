// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

private actor TaskFlowActor {
    private(set) var tasks: [[TaskFlow]] = []
    
    private var taskIds: [AnyHashable] = []
    
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
    
    func clear() {
        tasks.removeAll()
        taskIds.removeAll()
    }
}

public typealias TaskFlowHandler = (_ finish: (_ error: NSError?) -> Void) -> Void

public class TaskFlow: NSObject, @unchecked Sendable {
    private let actor = TaskFlowActor()
    
    let id: AnyHashable
    
    let flowHandler: TaskFlowHandler?
    
    let depends: [TaskFlow]?
    
    private var count: UInt = 1
    
    public init(_ flowHandler: TaskFlowHandler? = nil, id: AnyHashable = UUID.init().uuidString, count: UInt = 1, depends: [TaskFlow]? = nil) {
        self.flowHandler = flowHandler
        self.id = id
        self.count = count
        self.depends = depends
    }
    
    private var isFlowing: Bool = false
    
    private var isFinished: Bool = false {
        didSet {
            if isFinished == true {
                isFlowing = false
            }
        }
    }
    
    private class SendableHash: NSObject, @unchecked Sendable {
        let value: AnyHashable
        
        init(value: AnyHashable) {
            self.value = value
        }
    }
    
    private var failHandler: ((_ task: TaskFlow, _ error: Error) -> Void)?
}

extension TaskFlow {
    func queue(tasks: [TaskFlow]) async {
        if self.flowHandler != nil {
            if await self.actor.tasks.count == 0 {
                await self.actor.queue(tasks: [self])
            }
        }
        await self.actor.queue(tasks: tasks)
    }
    
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
                            Task {
                                await self.actor.remove(element.id)
                            }
                        }
                        element.isFinished = true
                        self.flowNext(tasks, current: current)
                    }
                }
            } else if element.count == 0 {
                Task {
                    await self.actor.remove(element.id)
                }
                flowNext(tasks, current: current)
            } else {
                element.isFinished = true
                flowNext(tasks, current: current)
            }
        }
    }
    
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
    
    func remove(_ id: AnyHashable) async {
        let hash = SendableHash(value: id)
        await self.actor.remove(hash.value)
    }
    
    func clear() async {
        await self.actor.clear()
    }
}

extension TaskFlow {
    static let main = TaskFlow()
}

public
extension NSObject {
    private struct TaskFlowAssociatedKey {
        nonisolated(unsafe) static var taskFlow: Void?
    }
    
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

internal extension NSObject {
    @discardableResult
    func synchronized<T>(_ closure: () -> T) -> T {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        return closure()
    }
}
