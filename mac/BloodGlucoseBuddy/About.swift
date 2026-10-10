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
            #if APP_STORE
            // Apple rejects apps that mention other platforms, so the App Store copy leaves Windows out.
            Text("This app is tiny on purpose. It does one thing: it puts my blood sugar next to the clock on my computer, so I can keep working without picking up my phone.")
            #else
            Text("This app is tiny on purpose. It does one thing: it puts my blood sugar next to the clock on my computer (Mac or Windows), so I can keep working without picking up my phone.")
            #endif
            Text("I thought about charging a dollar and couldn't do it. Something this simple should just be free, so it is, and it'll stay that way. It's also my first app on the App Store, which feels like a big deal to me.")
            Text("Making apps is how I pay my bills, though. If it's earned its spot next to your clock, a tip helps me keep going. No pressure at all.")
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
