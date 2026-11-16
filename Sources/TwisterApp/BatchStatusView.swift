import SwiftUI
import TwisterCore

/// Waiting tasks, the per-file status of the current conversion and earlier
/// conversions whose failed files still need a decision.
struct JobQueueView:View {
    @ObservedObject var state:AppState
    static func hasContent(_ state:AppState)->Bool { !state.queue.isEmpty || !state.unresolved.isEmpty || (state.batch?.items.count ?? 0)>1 }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            if !state.queue.isEmpty {
                HStack(spacing:8) {
                    Image(systemName:"clock").font(.system(size:11)).foregroundStyle(.secondary)
                    LText(state.queue.count==1 ? "1 task waiting":"\(state.queue.count) tasks waiting").font(.system(size:11,weight:.medium))
                    LText(state.queue[0].operation.title).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength:8)
                    Button { state.clearQueue() } label:{ LText("Clear queue") }.buttonStyle(TwisterButtonStyle(.quiet,compact:true))
                }.padding(.horizontal,15).padding(.vertical,9).twisterCard()
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
        VStack(alignment:.leading,spacing:11) {
            HStack(spacing:10) {
                Image(systemName:!batch.finished ? "square.stack.3d.up":report.failed>0 ? "exclamationmark.circle.fill":"checkmark.circle.fill")
                    .foregroundStyle(!batch.finished ? Color.secondary:report.failed>0 ? Color.orange:TwisterPalette.forest)
                VStack(alignment:.leading,spacing:3) {
                    LText(batch.job.operation.title).font(.system(size:12,weight:.semibold)).lineLimit(1)
                    LText(report.summary).font(.system(size:11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength:8)
                if batch.finished,report.failed>0 {
                    Button { state.retryFailed(batch) } label:{ LText("Retry failed") }.buttonStyle(TwisterButtonStyle(.secondary,compact:true))
                }
                Button { expanded = !showsFiles } label:{ Image(systemName:showsFiles ? "chevron.up":"chevron.down") }
                    .buttonStyle(TwisterButtonStyle(.quiet,compact:true)).accessibilityLabel(L10n.text(showsFiles ? "Hide files":"Show files"))
                if batch.finished {
                    Button { state.dismiss(batch) } label:{ Image(systemName:"xmark") }
                        .buttonStyle(TwisterButtonStyle(.quiet,compact:true)).accessibilityLabel(L10n.text("Dismiss results"))
                }
            }
            if showsFiles {
                Divider()
                if batch.items.count>6 { ScrollView { files }.frame(height:150) } else { files }
            }
        }.padding(15).twisterCard().twisterAnimation(value:showsFiles)
    }
    private var files:some View {
        VStack(alignment:.leading,spacing:7) {
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
                case .succeeded:Image(systemName:"checkmark.circle.fill").foregroundStyle(TwisterPalette.forest)
                case .failed:Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.orange)
                case .cancelled:Image(systemName:"minus.circle").foregroundStyle(.secondary)
                }
            }.font(.system(size:10)).frame(width:14,height:13)
            VStack(alignment:.leading,spacing:2) {
                Group { if item.inputs.count==1 { Text(item.inputs[0].lastPathComponent) } else { LText("\(item.inputs.count) files") } }
                    .font(.system(size:10)).lineLimit(1).truncationMode(.middle)
                if let reason=item.failure { LText(reason).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled) }
            }
            Spacer(minLength:8)
            LText(label).font(.system(size:10)).foregroundStyle(.secondary)
        }.accessibilityElement(children:.combine)
    }
}
