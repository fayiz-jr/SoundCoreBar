// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 fayiz-jr

import SwiftUI

/// A collapsible section for choosing the menu bar icon: symbols, emoji, or your own text.
struct IconPicker: View {
    @Binding var isExpanded: Bool
    @AppStorage(MenuBarIcon.storageKey) private var iconRawValue = MenuBarIcon.default.rawValue
    // `@State` is a compiler macro in the macOS 27 SDK and the Command Line Tools ship without its
    // plugin, so view state is declared with the `State` type directly; SwiftUI treats it the same.
    private let customText = State(initialValue: "")

    private var icon: MenuBarIcon { MenuBarIcon(rawValue: iconRawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.smooth) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("Menu Bar Icon")
                    Spacer()
                    icon.label.foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                iconGrid(MenuBarIcon.symbolChoices)
                iconGrid(MenuBarIcon.emojiChoices)
                HStack {
                    TextField("Your own emoji or text", text: customText.projectedValue)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(useCustomText)
                    Button("Use", action: useCustomText)
                        .disabled(MenuBarIcon.custom(customText.wrappedValue) == nil)
                }
            }
        }
    }

    private func iconGrid(_ choices: [MenuBarIcon]) -> some View {
        GlassGroup(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    GlassCircleButton(isSelected: choice == icon, diameter: 36) {
                        iconRawValue = choice.rawValue
                    } label: {
                        choice.label.font(.system(size: 15))
                    }
                    .accessibilityLabel(choice.accessibilityName)
                }
            }
        }
    }

    private func useCustomText() {
        guard let custom = MenuBarIcon.custom(customText.wrappedValue) else { return }
        iconRawValue = custom.rawValue
        customText.wrappedValue = ""
    }
}
