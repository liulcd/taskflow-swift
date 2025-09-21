// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

public extension TaskFlow {
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
        await observerTask?.queue([task])
        if initial == true {
            handleObserverUpdated(updated)
        }
        return task
    }
    
    func updateObservedValue(_ keyPath: String, value: Any?) async {
        let key = getObserverValueKey()
        let oldValue = await getProperty(key)
        await setProperty(oldValue, key: getObserverOldValueKey())
        await setProperty(value, key: key)
        guard let observerTask = await getObserverTasks()[keyPath] else { return }
        await observerTask.flow()
    }
    
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
    
    private func getObserverTasks() async -> [String: TaskFlow] {
        let key = getObserverTasksKey()
        guard let tasks = await getProperty(key) as? [String: TaskFlow] else {
            let tasks: [String: TaskFlow] = [:]
            await setProperty(tasks, key: key)
            return tasks
        }
        return tasks
    }
        
    private func getObserverTasksKey() -> String {
        return "\(self.id)_observerTasks"
    }
    
    private func getObserverValueKey() -> String {
        return "\(self.id)_observerValue"
    }
    
    private func getObserverOldValueKey() -> String {
        return "\(self.id)_observerOldValue"
    }
}


