import SwiftUI

/// The "About Maddie" window: why the app exists, and a no-pressure tip.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    #if APP_STORE
    @StateObject private var tips = TipJar()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                Text("Hi, I'm Maddie.").font(.title2.bold())
            }
            Text("I wear a Dexcom, and I'm at my computer most of the day. Blood Glucose Buddy started as a silly idea: what if my blood sugar just showed up under my name on Discord? It turned out it could. Then I noticed the part I actually looked at all day was the number sitting next to my clock, so that's what this is now.")
            Text("I'm autistic, and office jobs and I have never got on. So with my wife's support, I make small apps full-time, usually ones that fix something that bugged me. That's how I pay my bills.")
            Text("I wanted this one to be free for everyone who wears a Dexcom, so it is, and it'll stay that way. If it's earned its spot in your menu bar and you'd like to say thanks, a tip helps me keep making things like this. No pressure at all.")
            tipButtons
            Image("Signature").resizable().scaledToFit().frame(height: 40).foregroundStyle(.primary)
                .accessibilityLabel("Signed, Maddie")
            Link("More of my apps at tanookistudios.com", destination: URL(string: "https://tanookistudios.com")!)
                .font(.callout)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(width: 440)
    }

    @ViewBuilder private var tipButtons: some View {
        #if APP_STORE
        if tips.thanked {
            Text("Thank you. That genuinely helps.").font(.headline).foregroundStyle(.pink)
        } else if tips.products.isEmpty {
            Text(tips.problem ?? "Loading tips…").foregroundStyle(.secondary)
        } else {
            HStack {
                ForEach(tips.products, id: \.id) { product in
                    Button { Task { await tips.buy(product) } } label: {
                        VStack(spacing: 2) {
                            Text(product.displayPrice).font(.headline)
                            Text(TipJar.caption(product.id)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(tips.busy)
                }
            }
            if let problem = tips.problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
        }
        #else
        Button("Leave a Tip") { openURL(URL(string: "https://tanookistudios.com/SupportMe")!) }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("leaveTip")
        #endif
    }
}
