//
//  ImageActionView.swift
//  reminedo
//
//  이미지 알람의 행동(O 액션) 화면(§3.5). 순수 Black 풀스크린, 핀치/더블탭 확대,
//  아래로 쓸어내려 닫기 또는 항상 보이는 닫기 X, "쓸어내려 닫기" 힌트 1회(UserDefaults).
//  파일을 못 불러오면 "이미지를 불러올 수 없어요"(§8). 풀 이미지는 ImageStore로 로드한다.
//

import SwiftUI

struct ImageActionView: View {
    /// 디스크에서 로드할 파일명(O 액션·기존 저장본). preloaded가 있으면 무시한다.
    var fileName: String? = nil
    /// 이미 메모리에 있는 이미지(편집 시트에서 새로 고른 미저장 이미지 미리보기용).
    var preloaded: UIImage? = nil
    var onClose: () -> Void

    @Environment(ImageStore.self) private var imageStore

    @State private var image: UIImage?
    @State private var loaded = false

    // 줌/팬 상태.
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    // 아래로 쓸어내려 닫기(확대 아닐 때만).
    @State private var dragOffset: CGSize = .zero
    // "쓸어내려 닫기" 힌트 1회 노출(§3.5).
    @State private var showHint = false

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            content
                .offset(dragOffset)

            if showHint { hintBanner }

            closeButton
        }
        .onAppear(perform: loadIfNeeded)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification)
                    .simultaneousGesture(panOrDismiss(in: proxy.size))
                    .onTapGesture(count: 2) { toggleZoom() }
            }
        } else if loaded {
            // 파일 없음/깨짐(§8).
            VStack(spacing: 12) {
                Image(systemName: Tokens.Symbols.image)
                    .font(.system(size: 44))
                    .foregroundStyle(Tokens.Palette.textSecondary)
                Text(Strings.Action.imageLoadFailed)
                    .font(.subheadline)
                    .foregroundStyle(Tokens.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.white.opacity(0.15), in: Circle())
        }
        .padding(Tokens.Spacing.gutter)
        .accessibilityLabel(Strings.Action.close)
    }

    private var hintBanner: some View {
        VStack {
            Spacer()
            Text(Strings.Action.swipeDownHint)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, Tokens.Spacing.gutter)
                .padding(.vertical, Tokens.Spacing.row)
                .background(.white.opacity(0.18), in: Capsule())
                .padding(.bottom, 60)
                .transition(.opacity)
        }
    }

    // MARK: - 제스처

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale { resetZoom() }
            }
    }

    /// 확대 상태면 팬, 원본 크기면 아래로 쓸어내려 닫기(§3.5).
    private func panOrDismiss(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > minScale {
                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                } else {
                    dragOffset = CGSize(width: 0, height: max(0, value.translation.height))
                }
            }
            .onEnded { value in
                if scale > minScale {
                    lastOffset = offset
                } else if value.translation.height > 120 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
                }
            }
    }

    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if scale > minScale {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        scale = minScale
        lastScale = minScale
        offset = .zero
        lastOffset = .zero
    }

    // MARK: - 로드 / 힌트

    private func loadIfNeeded() {
        guard !loaded else { return }
        if let preloaded {
            image = preloaded
        } else if let fileName, !fileName.isEmpty {
            image = imageStore.loadImage(named: fileName)
        }
        loaded = true
        maybeShowHint()
    }

    /// "쓸어내려 닫기" 힌트 1회(§3.5) — 이미지를 정상 로드했을 때만.
    private func maybeShowHint() {
        guard image != nil else { return }
        let key = SharedConstants.UserDefaultsKey.hasSeenImageSwipeHint
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        withAnimation { showHint = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { showHint = false }
        }
    }
}

#Preview {
    ImageActionView(fileName: nil, onClose: {})
        .environment(ImageStore())
        .preferredColorScheme(.dark)
}
