//
//  DefaultPagerBar.swift
//  SegmentedPager
//
//  Plain built-in bar skin: equal-width titles with an underline
//  indicator interpolated from the continuous transition progress, so it
//  tracks the finger during swipes. Apps are expected to inject their
//  own skin through the `bar:` slot; this one keeps the package usable
//  standalone (demos, previews, spikes).
//

import SwiftUI

public struct DefaultPagerBar<Tab: Hashable>: View {
    private let context: PagerBarContext<Tab>
    private let title: (Tab) -> String

    public init(context: PagerBarContext<Tab>, title: @escaping (Tab) -> String) {
        self.context = context
        self.title = title
    }

    public var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(context.tabs, id: \.self) { tab in
                    Button {
                        context.select(tab)
                    } label: {
                        Text(title(tab))
                            .font(.subheadline)
                            .fontWeight(tab == context.selection ? .semibold : .regular)
                            .foregroundStyle(tab == context.selection ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == context.selection ? [.isSelected] : [])
                }
            }

            GeometryReader { proxy in
                let count = max(context.tabs.count, 1)
                let itemWidth = proxy.size.width / CGFloat(count)
                let inset: CGFloat = 12

                Capsule()
                    .fill(.tint)
                    .frame(width: max(itemWidth - inset * 2, 8), height: 3)
                    .offset(x: context.progress.position * itemWidth + inset)
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .contain)
    }
}
