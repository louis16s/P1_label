import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        EditorView(model: model)
            .toolbar {
                MainToolbar(model: model)
            }
            .task {
                await model.discoverPrinterAutomatically()
            }
            .alert("确认打印", isPresented: Binding(
                get: { model.pendingPrint?.source == .document },
                set: { if !$0 { model.cancelPendingPrint() } }
            )) {
                Button("取消", role: .cancel) { model.cancelPendingPrint() }
                Button("确认打印") { model.confirmPendingPrint() }
            } message: {
                Text(model.documentPrintConfirmationMessage)
            }
            .alert("保存更改？", isPresented: Binding(
                get: { model.pendingDocumentAction != nil },
                set: { presented in
                    if !presented, model.pendingDocumentAction != nil {
                        model.resolveUnsavedChanges(.cancel)
                    }
                }
            )) {
                Button("不保存", role: .destructive) {
                    model.resolveUnsavedChanges(.discard)
                }
                Button("取消", role: .cancel) {
                    model.resolveUnsavedChanges(.cancel)
                }
                Button("保存") {
                    model.resolveUnsavedChanges(.save)
                }
            } message: {
                Text(
                    "“\(model.document.name)”包含未保存的更改。要在\(model.pendingDocumentAction?.confirmationName ?? "继续")前保存吗？"
                )
            }
    }

}
