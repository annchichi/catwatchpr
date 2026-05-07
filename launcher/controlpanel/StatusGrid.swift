// launcher/controlpanel/StatusGrid.swift
import SwiftUI

struct StatusGrid: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("menubar", status: state.status.menubar)
            row("watch",   status: state.status.watch)
            row("sync",    status: state.status.sync)
            row("last check", text: state.status.lastChecked)
            row("open prs",   text: "\(state.status.openPRs)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatStyle.bg)
    }

    @ViewBuilder
    private func row(_ label: String, status: AgentStatus) -> some View {
        HStack {
            Text(label).foregroundColor(CatStyle.dim)
            Spacer()
            switch status {
            case .running:    Text("● running").foregroundColor(CatStyle.green)
            case .scheduled:  Text("● scheduled").foregroundColor(CatStyle.green)
            case .stopped:    Text("● stopped").foregroundColor(CatStyle.dim)
            case .crashed:    Text("● crashed").foregroundColor(CatStyle.red)
            }
        }
        .font(CatStyle.monoSmall)
    }

    @ViewBuilder
    private func row(_ label: String, text: String) -> some View {
        HStack {
            Text(label).foregroundColor(CatStyle.dim)
            Spacer()
            Text(text).foregroundColor(CatStyle.dim)
        }.font(CatStyle.monoSmall)
    }
}
