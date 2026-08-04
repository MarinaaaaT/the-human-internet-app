//
//  BrandMark.swift
//  the-human-internet
//

import SwiftUI

struct BrandMark: View {
    var size: CGFloat = 60
    var color: Color = Theme.accentPink

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(color)
                .frame(width: size, height: size * 0.22)
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(color)
                .frame(width: size * 0.5, height: size * 0.62)
                .offset(y: -size * 0.04)
        }
    }
}

#Preview {
    BrandMark(size: 100)
        .padding()
        .background(Theme.background)
}
