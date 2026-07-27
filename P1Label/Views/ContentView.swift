import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        EditorView(model: model)
            .toolbar {
                MainToolbar(model: model)
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
    }

}
