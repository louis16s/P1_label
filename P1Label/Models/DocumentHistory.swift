import Foundation

struct DocumentHistory {
    private static let maximumUndoCount = 100
    private static let coalescingInterval = 0.45

    private var undoStack: [LabelDocument] = []
    private var redoStack: [LabelDocument] = []
    private var lastEditDate = Date.distantPast
    private var savedDocument: LabelDocument

    init(savedDocument: LabelDocument) {
        self.savedDocument = savedDocument
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func isDirty(_ document: LabelDocument) -> Bool {
        document != savedDocument
    }

    mutating func recordChange(
        from previous: LabelDocument,
        at date: Date = Date()
    ) {
        if undoStack.isEmpty || date.timeIntervalSince(lastEditDate) > Self.coalescingInterval {
            undoStack.append(previous)
            if undoStack.count > Self.maximumUndoCount {
                undoStack.removeFirst(undoStack.count - Self.maximumUndoCount)
            }
        }
        lastEditDate = date
        redoStack.removeAll()
    }

    mutating func undo(current: LabelDocument) -> LabelDocument? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        lastEditDate = .distantPast
        return previous
    }

    mutating func redo(current: LabelDocument) -> LabelDocument? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        lastEditDate = .distantPast
        return next
    }

    mutating func reset(savedDocument: LabelDocument) {
        undoStack.removeAll()
        redoStack.removeAll()
        lastEditDate = .distantPast
        self.savedDocument = savedDocument
    }

    mutating func markSaved(_ document: LabelDocument) {
        savedDocument = document
    }
}
