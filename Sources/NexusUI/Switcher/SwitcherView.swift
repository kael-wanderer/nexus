import AppKit
import NexusCore
import SwiftUI

/// The full-screen window switcher (M25): a toolbar for filter/sort/group/stack, and a grid of
/// `SwitcherCard`s below it. Gated by Accessibility (no windows without it) and offered Screen
/// Recording in-panel rather than as an alert (design/window-switcher.md §5).
public struct SwitcherView: View {
    @Bindable var model: SwitcherViewModel

    public init(model: SwitcherViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.3)
            if model.showsAccessibilityGate {
                PermissionRequestView(
                    permission: .accessibility,
                    permissions: model.permissions,
                    onGrantTapped: { model.requestAccessibility() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if model.showsPreviewsOffer { previewsOffer }
                grid
            }
        }
        .background(.black.opacity(0.35))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker(String(localized: "Grouping"), selection: $model.grouping) {
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel(String(localized: "Flat"))
                    .tag(WindowSwitcherGrouping.flat)
                Image(systemName: "square.stack")
                    .accessibilityLabel(String(localized: "By Application"))
                    .tag(WindowSwitcherGrouping.application)
                Image(systemName: "display.2")
                    .accessibilityLabel(String(localized: "By Display"))
                    .tag(WindowSwitcherGrouping.display)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .accessibilityLabel(String(localized: "Grouping"))

            Button(String(localized: "Add Stack"), systemImage: "plus.rectangle.on.folder") {
                model.addStack()
            }
            .disabled(!model.canAddStack)

            Spacer()

            TextField(String(localized: "Filter…"), text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

            Spacer()

            Picker(String(localized: "Sort"), selection: $model.sort) {
                Text("Recent Apps").tag(WindowSwitcherSort.recent)
                Text("Application").tag(WindowSwitcherSort.application)
                Text("Window Title").tag(WindowSwitcherSort.title)
            }
            .labelsHidden()
            .frame(width: 160)
            .accessibilityLabel(String(localized: "Sort"))

            Button {
                model.isReversed.toggle()
            } label: {
                Image(systemName: model.isReversed ? "arrow.up" : "arrow.down")
            }
            .accessibilityLabel(String(localized: "Reverse the order"))
        }
        .padding(.horizontal, 16)
        .frame(height: SwitcherLayout.toolbarHeight)
    }

    private var previewsOffer: some View {
        HStack(spacing: 12) {
            Text("Turn on Screen Recording to see what is in each window.")
                .font(.callout)
            Button(String(localized: "Open Settings…")) { model.requestScreenRecording() }
            Button(String(localized: "Not Now")) { model.dismissPreviewsOffer() }
                .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private var grid: some View {
        GeometryReader { proxy in
            let columns = SwitcherLayout.columns(
                forWidth: proxy.size.width - 32,
                cardWidth: SwitcherLayout.cardWidth,
                spacing: SwitcherLayout.spacing
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.sections) { section in
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .accessibilityAddTraits(.isHeader)
                        }
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.fixed(SwitcherLayout.cardWidth), spacing: SwitcherLayout.spacing),
                                count: columns
                            ),
                            spacing: SwitcherLayout.spacing
                        ) {
                            ForEach(section.windows) { window in
                                SwitcherCard(
                                    window: window,
                                    preview: model.previews[window.identity.number],
                                    applicationURL: model.applicationURL(
                                        forBundleIdentifier: window.identity.owner.bundleIdentifier
                                    ),
                                    isSelected: model.selection.contains(window.id),
                                    isFocused: model.focused == window.id,
                                    onActivate: { model.activate(window) },
                                    onClose: { Task { await model.close(window) } },
                                    onToggleSelection: { model.toggleSelection(window.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: proxy.size.width) { _, _ in model.columns = columns }
            .onAppear { model.columns = columns }
        }
    }
}
