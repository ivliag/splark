import Observation

/// Calls `onChange` with what `read` returns now, then again after every change to the observable state it read.
@MainActor final class Watch {
    private var active = true

    init<Value>(_ read: @escaping @MainActor () -> Value, _ onChange: @escaping @MainActor (Value) -> Void) {
        track(read, onChange)
    }

    func cancel() { active = false }

    private func track<Value>(_ read: @escaping @MainActor () -> Value, _ onChange: @escaping @MainActor (Value) -> Void) {
        guard active else { return }
        // Observation calls back before the change lands: read again on the next turn of the main actor.
        let value = withObservationTracking(read) { [weak self] in
            Task { @MainActor in self?.track(read, onChange) }
        }
        onChange(value)
    }
}
