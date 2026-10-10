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
            Text("My wife has followed my Dexcom since last year. When I went looking for a way to see my own number on my computer, I found out Dexcom's official feed for apps runs an hour behind. An hour late is no use to anyone, so I built this on the same live feed my wife's phone uses.")
            Text("I spend ten to twelve hours a day at my desk making apps, and this turned out to be the most useful thing on my screen. It's also my first app on the App Store.")
            Text("It's free, and it'll stay free. But apps are my whole income, and some things wait on money. The Windows version is still unsigned because I can't afford the certificate yet, so Windows warns people away from it. If this has earned its spot next to your clock, a tip goes straight into things like that. No pressure at all.")
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
