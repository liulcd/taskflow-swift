# TaskFlow

TaskFlow is a lightweight Swift library for managing asynchronous task flows with dependencies. It allows you to define tasks, set dependencies, and execute them in the correct order, supporting error handling and repeatable tasks.

## Features

- Define asynchronous tasks with custom logic
- Set dependencies between tasks
- Automatic execution order based on dependencies
- Error handling and repeat count support
- Thread-safe and actor-based implementation
- Thread-safe key-value property storage for each task

## Installation

Add the following to your `Package.swift`:

```swift
.package(url: "https://github.com/liulcd/taskflow-swift.git", from: "1.0.0")
```


## Observer Extension

TaskFlow provides an observer extension that allows you to react to value changes asynchronously or synchronously. You can register observer tasks for specific key paths and get notified when values are updated. Observer state is managed via thread-safe properties on each task instance.

### Example: Observing Value Changes

```swift
import TaskFlow

let flow = TaskFlow()
let observer = NSObject()

// Add an observer for a keyPath (async)
let observerTask = flow.addObserverTask(observer, keyPath: "username") { newValue, oldValue in
	print("username changed from \(String(describing: oldValue)) to \(String(describing: newValue))")
}

// Update the observed value (async)
await flow.updateObservedValue("username", value: "Alice")
await flow.updateObservedValue("username", value: "Bob")

// Or update synchronously (will dispatch async internally)
flow.updateObservedValue("username", value: "Charlie")

// Remove the observer task when no longer needed
await flow.removeObserverTask(observerTask)
```
- Observer extension supports both async and sync value change notifications


### 1. Define Tasks and Use Properties

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
import TaskFlow

let task = TaskFlow { finish in
	// Set a custom property
	task.properties["userId"] = 123
	// Access property later
	print("userId:", task.properties["userId"] ?? "nil")
	finish(nil)
}


### 2. Use finishHandler and finish

You can use the `finishHandler` property to define a custom completion callback for a task, and call `finish()` to mark the task as complete:

```swift
let task = TaskFlow { finish in
	// ... do work ...
	finish(nil) // or finish(error)
}
task.finishHandler = { error in
	if let error = error {
		print("Task failed: \(error)")
	} else {
		print("Task finished successfully")
	}
}
```

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
