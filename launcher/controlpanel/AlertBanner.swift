// launcher/controlpanel/AlertBanner.swift
import SwiftUI

struct AlertBanner: View {
    let excerpt: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("⚠ MENUBAR AGENT CRASHED")
                .font(CatStyle.monoTiny).tracking(1.5)
                .foregroundColor(CatStyle.red)
            Text(excerpt).font(CatStyle.monoSmall)
                .foregroundColor(Color(red:1.0,green:0.69,blue:0.75))
                .lineLimit(2).multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red:1.0,green:0.33,blue:0.46).opacity(0.08))
        .overlay(Rectangle().frame(width:3).foregroundColor(CatStyle.red),
                 alignment: .leading)
    }
}
