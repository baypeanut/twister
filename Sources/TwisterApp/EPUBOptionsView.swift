import SwiftUI
import TwisterCore

struct EPUBOptionsView:View {
    @ObservedObject var state:AppState
    let inputs:[URL]
    @State private var layout="reflowable"
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Picker("Layout",selection:$layout) { Text("Flexible, reflowable text").tag("reflowable");Text("Keep the original pages").tag("fixed") }.pickerStyle(.radioGroup)
            LText(layout=="fixed" ? "Keeps the look and dimensions of each page. Best for visual layouts.":"Text adapts to the reader’s screen and font size. Best for reading.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:0)
            JobProgressView(state:state)
            HStack { SavePresetButton { var options=FormatPreferences.shared.options(for:"epub");options.epubLayout=layout;PresetPrompt.save(.convert("epub"),options:options,state:state) };Spacer();Button("Make EPUB") { var options=FormatPreferences.shared.options(for:"epub");options.epubLayout=layout;state.execute(.convert("epub"),options:options,inputs:inputs) }.keyboardShortcut(.defaultAction).disabled(state.working) }
        }.padding(20).frame(minWidth:420,minHeight:220).background(Color(nsColor:.windowBackgroundColor)).twisterAnimation(value:layout).onAppear { layout=FormatPreferences.shared.profile(for:"epub").epubLayout }
    }
}
