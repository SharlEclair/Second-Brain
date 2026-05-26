import ActivityKit
import WidgetKit
import SwiftUI

struct IngestionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic properties
        var status: String
        var progress: Double
    }

    // Static properties
    var title: String
    var url: String
}

// NOTE: In Xcode, this file should be part of a separate Widget Extension target.
// The @main attribute belongs on the WidgetBundle in that target's context.
// When adding to a Widget Extension target in Xcode, uncomment the @main below.
// @main
struct CortexWidgetBundle: WidgetBundle {
    var body: some Widget {
        CortexAgendaWidget()
        CortexLiveActivity()
    }
}


struct CortexLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IngestionAttributes.self) { context in
            // Lock Screen/Notification UI
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label {
                        Text("CORTEX VAULT")
                            .font(.system(.caption, design: .monospaced))
                            .bold()
                            .foregroundColor(Color("WidgetAccent"))
                    } icon: {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(Color("WidgetAccent"))
                    }
                    Spacer()
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .foregroundColor(Color("WidgetTextSecondary"))
                }
                
                Text(context.state.status)
                    .font(.system(.headline, design: .default))
                    .foregroundColor(Color("WidgetTextPrimary"))
                
                Text(context.attributes.url)
                    .font(.system(.caption, design: .default))
                    .foregroundColor(Color("WidgetTextSecondary"))
                    .lineLimit(1)
                
                // Subtle Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color("WidgetDivider"))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color("WidgetAccent"))
                            .frame(width: geometry.size.width * CGFloat(context.state.progress), height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding()
            .background(Color("WidgetBackground"))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("Cortex Vault")
                            .font(.headline)
                            .foregroundColor(Color("WidgetAccent"))
                    } icon: {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(Color("WidgetAccent"))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.title3)
                        .bold()
                        .foregroundColor(Color("WidgetAccent"))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.status)
                            .font(.subheadline)
                            .foregroundColor(Color("WidgetTextPrimary"))
                        
                        Text(context.attributes.url)
                            .font(.caption)
                            .foregroundColor(Color("WidgetTextSecondary"))
                            .lineLimit(1)
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color("WidgetDivider"))
                                    .frame(height: 3)
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color("WidgetAccent"))
                                    .frame(width: geometry.size.width * CGFloat(context.state.progress), height: 3)
                            }
                        }
                        .frame(height: 3)
                    }
                }
            } compactLeading: {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(Color("WidgetAccent"))
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .foregroundColor(Color("WidgetAccent"))
                    .font(.caption2)
                    .bold()
            } minimal: {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(Color("WidgetAccent"))
            }
            .keylineTint(Color("WidgetAccent"))
        }
    }
}
