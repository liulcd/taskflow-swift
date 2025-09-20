# taskflow-swift

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

## Usage

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
	await taskC.queue(tasks: [taskA, taskB, taskC])
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

## License

MIT
