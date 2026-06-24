//
//  LockScreenActionView.swift
//  reminedo
//
//  Full-screen reminder action surface shown after tapping a notification.
//

import SwiftUI

struct LockScreenActionView: View {
    let title: String
    let scheduledAt: Date
    let snoozeEnabled: Bool
    let snoozeMinutes: Int

    var onSnooze: () -> Void
    var onDismiss: () -> Void
    var onOpen: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                clockBlock
                    .padding(.top, 54)

                Spacer(minLength: 28)

                identityBlock

                Spacer(minLength: 28)

                actionButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
            }
        }
    }

    private var clockBlock: some View {
        VStack(spacing: 8) {
            Text(DateFormatting.lockDateText())
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.82))

            Text(DateFormatting.lockClockText(scheduledAt))
                .font(.system(size: 108, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
    }

    private var identityBlock: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 142, height: 142)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .accessibilityHidden(true)

            Text(Strings.Action.brand)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Tokens.Palette.accent)

            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 28)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            if snoozeEnabled {
                LockActionButton(
                    title: Strings.Action.snoozeButton(snoozeMinutes),
                    symbolName: "clock.arrow.circlepath",
                    tint: Tokens.Palette.accent,
                    action: onSnooze
                )
            }

            LockActionButton(
                title: Strings.Action.dismissButton,
                symbolName: "xmark",
                tint: Tokens.Palette.destructive,
                action: onDismiss
            )

            LockActionButton(
                title: Strings.Action.openButton,
                symbolName: "play.fill",
                tint: Tokens.Palette.accent,
                action: onOpen
            )
        }
    }
}

private struct LockActionButton: View {
    let title: String
    let symbolName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.10))
                    .shadow(color: tint.opacity(0.38), radius: 18, x: 0, y: 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(tint, lineWidth: 1.2)
                    )

                HStack {
                    Image(systemName: symbolName)
                        .font(.system(size: 26, weight: .medium))
                        .frame(width: 48)

                    Spacer(minLength: 0)

                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    Color.clear.frame(width: 48)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 22)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LockScreenActionView(
        title: "유튜브 영상 보기",
        scheduledAt: Date(),
        snoozeEnabled: true,
        snoozeMinutes: 5,
        onSnooze: {},
        onDismiss: {},
        onOpen: {}
    )
    .preferredColorScheme(.dark)
}
