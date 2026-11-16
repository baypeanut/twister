import SwiftUI
import TwisterCore

struct EPUBOptionsView:View {
    @ObservedObject var state:AppState
    let inputs:[URL]
    @State private var layout="reflowable"
    var body:some View {
        VStack(alignment:.leading,spacing:22) {
            TwisterPageHeading(eyebrow:"PDF → EPUB",title:"A good read, your way.",subtitle:"Choose how your pages make the move.")
            VStack(alignment:.leading,spacing:13) {
                Picker("Layout",selection:$layout) { Text("Flexible, reflowable text").tag("reflowable");Text("Keep the original pages").tag("fixed") }.pickerStyle(.radioGroup)
                Text(layout=="fixed" ? "Keeps the look and dimensions of each page. Best for visual layouts.":"Text adapts to the reader’s screen and font size. Best for reading.").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(19).twisterCard(radius:18)
            HStack { Label("Your original stays safe",systemImage:"lock").font(.system(size:10)).foregroundStyle(.secondary);Spacer();SavePresetButton { var options=FormatPreferences.shared.options(for:"epub");options.epubLayout=layout;PresetPrompt.save(.convert("epub"),options:options,state:state) };Button("Make EPUB") { var options=FormatPreferences.shared.options(for:"epub");options.epubLayout=layout;state.execute(.convert("epub"),options:options,inputs:inputs) }.buttonStyle(TwisterButtonStyle(.primary)).disabled(state.working) }
            JobProgressView(state:state)
        }.padding(28).frame(minWidth:470,minHeight:310).background(TwisterPalette.canvas).tint(.twister).twisterAnimation(value:layout).onAppear { layout=FormatPreferences.shared.profile(for:"epub").epubLayout }
    }
}
