import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct PinTransportPicker: View {
    @Environment(\.theme) private var theme
    @Binding var selection: TransportKind?
    var availableTransports: Set<TransportKind>

    public init(selection: Binding<TransportKind?>, availableTransports: Set<TransportKind>) {
        self._selection = selection
        self.availableTransports = availableTransports
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Preferred transport").font(Typography.label).foregroundStyle(theme.colors.text2)
            HStack(spacing: Spacing.xs + 2) {
                option(.adb, label: "ADB")
                option(.mtp, label: "MTP")
                autoOption
            }
        }
    }

    @ViewBuilder
    private func option(_ kind: TransportKind, label: String) -> some View {
        Button {
            selection = selection == kind ? nil : kind
        } label: {
            HStack(spacing: 4) {
                IconChip(label, kind: chipKind(for: kind))
                if selection == kind {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selection == kind ? theme.colors.accentSoft : theme.colors.background1.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .disabled(!availableTransports.contains(kind))
        .opacity(availableTransports.contains(kind) ? 1.0 : 0.4)
    }

    private var autoOption: some View {
        Button {
            selection = nil
        } label: {
            Text("Auto")
                .font(Typography.captionEmphasized)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(selection == nil ? theme.colors.accentSoft : theme.colors.background1.opacity(0.4))
                )
        }
        .buttonStyle(.plain)
    }

    private func chipKind(for kind: TransportKind) -> IconChipKind {
        switch kind {
        case .adb: .adb
        case .mtp: .mtp
        case .wifi: .wifi
        }
    }
}
