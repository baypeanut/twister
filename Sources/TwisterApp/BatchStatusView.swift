import SwiftUI
import TwisterCore

/// Waiting tasks, the per-file status of the current conversion and earlier
/// conversions whose failed files still need a decision.
struct JobQueueView:View {
    @ObservedObject var state:AppState
    static func hasContent(_ state:AppState)->Bool { !state.queue.isEmpty || !state.unresolved.isEmpty || (state.batch?.items.count ?? 0)>1 }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if !state.queue.isEmpty {
                HStack(spacing:8) {
                    LText(state.queue.count==1 ? "1 task waiting":"\(state.queue.count) tasks waiting")
                    LText(state.queue[0].operation.title).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength:8)
                    Button { state.clearQueue() } label:{ LText("Clear Queue") }.controlSize(.small)
                }.padding(.horizontal,12).padding(.vertical,8).twisterGroup()
            }
            if let batch=state.batch,batch.items.count>1 { BatchStatusView(state:state,batch:batch) }
            ForEach(state.unresolved) { BatchStatusView(state:state,batch:$0) }
        }.twisterAnimation(value:state.queue.count).twisterAnimation(value:state.unresolved.count)
    }
}

struct BatchStatusView:View {
    @ObservedObject var state:AppState
    let batch:JobBatch
    /// Until the user chooses, the files are listed while they run and when some failed.
    @State private var expanded:Bool?
    private var report:BatchReport { batch.report }
    private var showsFiles:Bool { expanded ?? (!batch.finished || report.failed>0) }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                Group {
                    if !batch.finished { ProgressView().controlSize(.small) }
                    else if report.failed>0 { Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor) }
                    else { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }
                }.frame(width:18).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:2) {
                    LText(batch.job.operation.title).lineLimit(1)
                    LText(report.summary).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength:8)
                if batch.finished,report.failed>0 {
                    Button { state.retryFailed(batch) } label:{ LText("Retry Failed").lineLimit(1).fixedSize() }.controlSize(.small)
                }
                Button { expanded = !showsFiles } label:{ Image(systemName:"chevron.right").rotationEffect(.degrees(showsFiles ? 90:0)) }
                    .buttonStyle(.borderless).accessibilityLabel(L10n.text(showsFiles ? "Hide files":"Show files"))
                if batch.finished {
                    Button { state.dismiss(batch) } label:{ Image(systemName:"xmark") }
                        .buttonStyle(.borderless).accessibilityLabel(L10n.text("Dismiss results"))
                }
            }
            if showsFiles {
                Divider()
                if batch.items.count>6 { ScrollView { files }.frame(height:150) } else { files }
            }
        }.padding(12).twisterGroup().twisterAnimation(value:showsFiles)
    }
    private var files:some View {
        VStack(alignment:.leading,spacing:6) {
            ForEach(Array(batch.items.enumerated()),id:\.offset) { _,item in BatchItemRow(item:item) }
        }
    }
}

private struct BatchItemRow:View {
    let item:BatchItem
    private var label:String {
        switch item.status {
        case .pending:return "Waiting"
        case .running:return "Working…"
        case .succeeded:return "Done"
        case .failed:return "Failed"
        case .cancelled:return "Cancelled"
        }
    }
    var body:some View {
        HStack(alignment:.top,spacing:8) {
            Group {
                switch item.status {
                case .pending:Image(systemName:"clock").foregroundStyle(.secondary)
                case .running:ProgressView().controlSize(.mini)
                case .succeeded:Image(systemName:"checkmark.circle.fill").foregroundStyle(.green)
                case .failed:Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                case .cancelled:Image(systemName:"minus.circle").foregroundStyle(.secondary)
                }
            }.font(.subheadline).frame(width:18,height:14)
            VStack(alignment:.leading,spacing:2) {
                Group { if item.inputs.count==1 { Text(item.inputs[0].lastPathComponent) } else { LText("\(item.inputs.count) files") } }
                    .lineLimit(1).truncationMode(.middle)
                if let reason=item.failure { LText(reason).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
            }
            Spacer(minLength:8)
            LText(label).foregroundStyle(.secondary)
        }.font(.subheadline).accessibilityElement(children:.combine)
    }
}
