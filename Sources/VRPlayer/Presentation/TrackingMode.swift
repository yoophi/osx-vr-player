enum TrackingMode {
    case off, outlines, hidden

    var next: Self {
        switch self {
        case .off: return .outlines
        case .outlines: return .hidden
        case .hidden: return .off
        }
    }

    var label: String {
        switch self {
        case .off: return "트래킹 하지 않음"
        case .outlines: return "얼굴 인식 사각형 표시"
        case .hidden: return "사각형 표시하지 않지만 선택영역 트래킹"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "eye.slash"
        case .outlines: return "viewfinder"
        case .hidden: return "scope"
        }
    }
}
