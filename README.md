# TaskFlow

TaskFlow is a lightweight Swift library for managing asynchronous task flows with dependencies. It allows you to define tasks, set dependencies, and execute them in the correct order, supporting error handling and repeatable tasks.

## Features

- Define asynchronous tasks with custom logic
- Set dependencies between tasks
- Automatic execution order based on dependencies
- Error handling and repeat count support
- Thread-safe and actor-based implementation

## Installation

Add the following to your `Package.swift`:

```swift
.package(url: "https://github.com/liulcd/taskflow-swift.git", from: "1.0.0")
```


## Observer Extension

TaskFlow provides an observer extension that allows you to react to value changes asynchronously. You can register observer tasks for specific key paths and get notified when values are updated.

### Example: Observing Value Changes

```swift
import TaskFlow

let flow = TaskFlow()
let observer = NSObject()

// Add an observer for a keyPath
let observerTask = await flow.addObserverTask(observer, keyPath: "username") { newValue, oldValue in
    print("username changed from \(String(describing: oldValue)) to \(String(describing: newValue))")
}

// Update the observed value
await flow.updateObservedValue("username", value: "Alice")
await flow.updateObservedValue("username", value: "Bob")

// Remove the observer task when no longer needed
await flow.removeObserverTask(observerTask)
```

### 1. Define Tasks

```swift
import TaskFlow

let taskA = TaskFlow { finish in
	print("Task A started")
	// Simulate async work
	DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
		print("Task A finished")
		finish(nil)
	}
}

let taskB = TaskFlow { finish in
	print("Task B started")
	finish(nil)
}

let taskC = TaskFlow({ finish in
	print("Task C started")
	finish(nil)
}, depends: [taskA, taskB]) // taskC depends on taskA and taskB
```

### 2. Queue and Execute Tasks

```swift
Task {
	await taskC.queue([taskA, taskB, taskC])
	await taskC.flow { failedTask, error in
		print("Task \(failedTask.id) failed: \(error)")
	}
}
```

### 3. Remove or Clear Tasks

```swift
Task {
	await taskC.remove(taskA.id)
	await taskC.clear()
}
```

> **Note:**
> - One-shot tasks (tasks with no repeat count) are automatically removed from the queue after successful completion.
> - Tasks with a repeat count are also automatically removed when their execution count is exhausted.


## License

See [LICENSE](LICENSE) for details.
